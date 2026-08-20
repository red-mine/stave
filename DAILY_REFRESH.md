# 每日数据刷新

## 快速使用

### 方式 1：双击运行（Windows，最简单）
双击 `daily_refresh.bat`，等待完成即可。

### 方式 2：PowerShell（Windows）
```powershell
.\bin\daily-refresh.ps1
```

### 方式 3：手动命令
```powershell
$env:Path = "C:\Ruby34-x64\bin;" + $env:Path
$env:TDX_DATA_PATH = "C:\new_tdx\vipdoc"
cd C:\Users\huntl\work\stave
bundle exec rails daily_refresh
```

## 前提条件

1. **通达信数据已更新** — 先打开通达信，下载当日日线数据
2. **Ruby 3.4 可用** — 脚本已内置路径设置

## 频率建议

- **交易日每天一次** — 收盘后、次日开盘前运行
- **不要重复运行** — `daily_refresh` 有锁机制，同一天不会重复处理

## 什么时候可以回测

连续运行 **20 个交易日** 后，才能看到回测报告：

```powershell
bundle exec rails backtest[sz]
bundle exec rails backtest[sh]
```

## 定时自动运行（Windows）

以 PowerShell 安装每日 20:30 运行的任务计划：

```powershell
.\bin\install-daily-refresh-task.ps1
```

## 定时自动运行（Linux）

systemd 用户定时器是主要方式，默认每天 20:30 刷新，每周清理日志：

```sh
bin/install-daily-refresh-timer.sh
systemctl --user list-timers stave-daily-refresh.timer stave-retention.timer
```

如果系统不支持 systemd 用户服务，仍可使用已弃用的 cron 兼容安装器：

```sh
bin/install-daily-refresh-cron.sh
```
