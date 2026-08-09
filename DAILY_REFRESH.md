# 每日数据刷新

## 快速使用

### 方式 1：双击运行（最简单）
双击 `daily_refresh.bat`，等待完成即可。

### 方式 2：PowerShell
```powershell
.\daily_refresh.ps1
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

## 定时自动运行（Windows 任务计划程序）

1. 打开「任务计划程序」
2. 创建基本任务 → 名称：`StockStaveDailyRefresh`
3. 触发器：每天 18:00（收盘后，通达信数据已更新）
4. 操作：启动程序
5. 程序：`C:\Users\huntl\work\stave\daily_refresh.bat`
6. 起始于：`C:\Users\huntl\work\stave`
