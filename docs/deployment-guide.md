# 分步部署指导

> 面向 Windows 环境的可复制命令清单。所有命令均在 PowerShell 中执行。

---

## 0. 环境检查

```powershell
terraform version
# 预期：Terraform v1.5.0 或更高

python --version
# 预期：Python 3.x（用于打包脚本）
```

---

## 1. 准备部署参数

```powershell
cd <本仓库根目录>
Copy-Item infra\terraform.tfvars.example infra\terraform.tfvars
```

编辑 `infra\terraform.tfvars`，填写以下必填项：

| 变量 | 填写内容 |
|---|---|
| `obs_bucket_name` | 全局唯一的桶名，建议带项目前缀与随机后缀 |
| `code_bucket_name` | 存放函数代码包的桶名，可与上一项相同 |
| `geminidb_password` | 宽表实例管理员密码 |
| `apig_appcode` | 应用认证 AppCode |

> 敏感项建议通过环境变量传入，避免写入文件：
> ```powershell
> $env:TF_VAR_geminidb_password = "<password>"
> $env:TF_VAR_apig_appcode      = "<appcode>"
> ```

---

## 2. 配置访问凭据

```powershell
$env:HW_ACCESS_KEY = "<your-access-key>"
$env:HW_SECRET_KEY = "<your-secret-key>"
```

> 密钥从控制台「我的凭证 → 访问密钥」获取。不要写入任何文件。

---

## 3. 打包函数代码

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package-function.ps1
```

**预期输出**：产物路径 `dist\token-handler.zip` 与体积（数百 KB 以上）。若体积过小，脚本会直接报错，说明依赖未打入包中。

---

## 4. 代码包对象

代码包由部署过程自动上传到对象存储，并在创建函数时下发给函数——`code_zip_path` 已指向 `dist\token-handler.zip`，**无需手工上传**。

> 如需改为手工上传：把 `terraform.tfvars` 中的 `code_zip_path` 置空，自行将代码包上传到 `code_object_key` 指定的对象键。

---

## 5. 初始化与预演

```powershell
cd infra
terraform init
terraform plan -out=tfplan
```

**预期输出**：`Plan: N to add, 0 to change, 0 to destroy.`

---

## 6. 部署

```powershell
terraform apply tfplan
```

**预期输出**：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

**耗时**：约 10-15 分钟，主要是宽表实例初始化与网关实例启动。

---

## 7. 读取输出

```powershell
terraform output
terraform output -raw api_base_url
terraform output -raw apig_appcode
```

记录 `api_base_url`、`token_endpoint`、`obs_bucket_name`、`geminidb_endpoint`、`geminidb_port`、`function_urn`。

---

## 8. 业务验证

参见主文档第 9 节的 5 项验证：申请 token → 换取签名 URL → 取对象 → 重放被拒 → 限流生效。

---

## 9. 常见问题排查

### 9.1 函数日志为空

函数日志从入口函数开始采集。若日志完全为空，优先检查代码包是否真正加载：

```powershell
terraform state show module.functiongraph.huaweicloud_fgs_function.token_handler
# 关注 code_size 字段；为空表示代码未挂载
```

处理方式：确认代码包对象已上传，然后重建函数。

```powershell
terraform apply -replace="module.functiongraph.huaweicloud_fgs_function.token_handler"
```

### 9.2 函数连接数据库超时

1. 确认 `geminidb_endpoint` 与 `geminidb_port` 与实例实际形态一致（集群形态端口为 80）
2. 确认函数与实例在同一 VPC 与子网
3. 确认安全组放通同组互访

### 9.3 签名 URL 取对象返回 403

1. 确认 URL 未过期
2. 确认函数执行委托已授予对象存储访问角色
3. 确认桶策略已放通委托读取目标对象

### 9.4 请求返回 429

触发限流策略。调整 `apig_max_api_requests` 或降低调用频率后重新部署。

---

## 10. 释放资源

```powershell
cd infra
terraform destroy -auto-approve
```

**预期输出**：`Destroy complete! Resources: N destroyed.`

> 收工后请确认无残留实例；若存在手工创建的资源（如手工上传的对象），需在控制台单独清理。
