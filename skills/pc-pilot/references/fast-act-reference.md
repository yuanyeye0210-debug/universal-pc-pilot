# `fast-act` v2.0 参数与动作参考手册

## 1. 命令行参数

```powershell
fast-act -ProcessName <进程名> [-WindowTitle <标题关键字>] -ActionsJson '<JSON数组>' [选项]
```

| 参数 | 说明 |
| :--- | :--- |
| `-ProcessName` | 目标进程名（不含 `.exe`，如 `WeChat`、`Feishu`、`notepad`） |
| `-WindowTitle` | 可选，窗口标题模糊匹配（`*关键字*`） |
| `-ActionsJson` | 必填，单个动作对象或动作数组 JSON 字符串 |
| `-CapturePath` | 可选，结束或让权时保存核验截图路径（自动内嵌 `100px` 刻度尺与红点准星） |
| `-NoMaximize` | 可选，保持目标窗口当前大小，不自动最大化 |
| `-NoRuler` | 可选，关闭核验截图上的坐标刻度尺 |
| `-ReturnFocus` | 可选，操作完成后自动置顶弹回调用方 Agent/终端窗口 |
| `-ReturnProcess` | 可选，显式指定弹回的进程名（如 `Cursor`、`Code`、`Antigravity`、`WindowsTerminal`） |

---

## 2. 支持的动作类型（JSON Schema）

| `type` | 必填/可选字段 | 作用说明 |
| :--- | :--- | :--- |
| `click` | `rx, ry` 或 `x, y`（加 `relative: true`） | 左键单击（带目标窗口边界越界拦截） |
| `dblclick` | 同上 | 左键双击 |
| `rightclick` | 同上 | 右键单击 |
| `clickName` | `name`, 可选 `button:"right"`, `double:true` | 通过 Windows UIA 按控件文本定位中心并点击 |
| `scroll` | `clicks`（负数为向下滚，如 `-5`）, 可选 `rx, ry` | 在指定坐标或窗口中心滚动鼠标滚轮 |
| `drag` | `fromRx, fromRy, toRx, toRy`（或 `fromX/Y, toX/Y`）, 可选 `steps` | 平滑拖拽（默认 10 步插值） |
| `paste` | `text`, 可选 `clear: false` | 默认先 `Ctrl+A -> Backspace` 清空后粘贴，自动备份还原剪贴板 |
| `typeText` | `text`, 可选 `clear: true` | 自动转义 `+ ^ % ~ ( ) { } [ ]` 逐字输入（专治禁粘贴密码框） |
| `key` | `keys`（SendKeys 语法，如 `^f`, `{ENTER}`, `%{F4}`） | 发送快捷键或功能键 |
| `assertOcr` | `contains`, 可选 `rx, ry, w, h` | 本地 WinRT OCR 校验区域文字是否包含目标字串，不匹配立即退出（exit 7） |
| `readOcr` | `rx, ry, w, h`, 可选 `label` | 本地 WinRT OCR 提取区域纯文本并输出，免传大图 |
| `focusPopup` | 无 | 当同进程弹出模态子窗口/对话框时，将相对坐标上下文切换至该子窗口 |
| `wait` | `ms` | 分片等待（每 60ms 检测一次用户鼠标/键盘介入） |
| `waitTitle` | `title`, 可选 `timeoutMs`（默认 3000） | 等待新窗口标题出现并自动切换焦点，超时中止（exit 5） |

---

## 3. 退出码说明

- `0`：全部动作执行成功（或检测到用户介入后安全让权并等待 2.5s 完成交接）
- `1`：未找到目标进程或窗口
- `2`：动作中途焦点离开目标进程，已安全中止
- `3`：未知动作 `type`
- `4`：点击/拖拽坐标超出目标窗口范围，已拦截
- `5`：`waitTitle` 等待窗口超时
- `6`：`clickName` 未找到对应 UIA 控件
- `7`：`assertOcr` 校验未通过或系统无可用 OCR 语言包
