# 打包函数代码为 zip（供对象存储下发）。
#
# 要点：
#   - 对象存储客户端由运行环境内置，不随包携带（自带反而会引入本机原生扩展）
#   - 依赖按 Linux x86_64 轮子安装，避免打包机平台差异
#   - 编译扩展（*.so）必须保留，否则 pydantic 等依赖在运行环境无法导入
#   - 过滤 __pycache__ / 测试 / 元数据目录
#   - 体积护栏：产物过小即报错，避免产出空包

param(
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist'),
    [string]$Python = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-Python {
    param([string]$Preferred)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Preferred)) { $candidates += $Preferred }
    else { $candidates += @('python', 'python3', 'py') }

    foreach ($cand in $candidates) {
        try {
            $ver = & $cand -c "import sys;print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and $ver) {
                Write-Host "==> 使用 Python：$cand ($ver)"
                return $cand
            }
        } catch { }
    }
    throw '未找到可用的 Python 解释器。请安装 Python 3，或用 -Python <完整路径> 指定。'
}

$pythonExe = Resolve-Python -Preferred $Python

& $pythonExe -m pip --version > $null 2>&1
if ($LASTEXITCODE -ne 0) { throw "所选解释器缺少 pip：$pythonExe" }

$root    = Resolve-Path (Join-Path $PSScriptRoot '..')
$srcDir  = Join-Path $root 'src\functions'
$build   = Join-Path $OutDir 'build'
$zipPath = Join-Path $OutDir 'token-handler.zip'

Write-Host '==> 清理构建目录'
if (Test-Path $build)   { Remove-Item $build -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
New-Item -ItemType Directory -Path $build -Force | Out-Null

Write-Host '==> 安装依赖（Linux x86_64 轮子，仅二进制）'
& $pythonExe -m pip install `
    --target $build `
    --platform manylinux2014_x86_64 `
    --python-version 39 `
    --only-binary=:all: `
    --upgrade `
    -r (Join-Path $srcDir 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw "依赖安装失败（退出码 $LASTEXITCODE）。" }

Write-Host '==> 复制函数代码'
Copy-Item (Join-Path $srcDir 'handler.py') $build -Force
Copy-Item (Join-Path $srcDir 'models.py')  $build -Force

Write-Host '==> 过滤构建噪声'
Get-ChildItem $build -Recurse -Directory -Force |
    Where-Object { $_.Name -in @('__pycache__', 'tests', 'test') -or $_.Name -like '*.dist-info' -or $_.Name -like '*.egg-info' } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
# 只剥离 Windows 原生扩展；本包按 Linux 轮子构建，须保留 .so（编译扩展模块）
Get-ChildItem $build -Recurse -File -Force -Include '*.pyc', '*.pyo', '*.pyd' |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host '==> 压缩'
Compress-Archive -Path (Join-Path $build '*') -DestinationPath $zipPath -Force

$sizeKb = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
Write-Host "==> 产物：$zipPath ($sizeKb KB)"
if ($sizeKb -lt 200) {
    throw "产物过小（$sizeKb KB），依赖可能未打入包中。"
}
