# LockPower

LockPower 会在屏幕锁定或显示器休眠一段时间后自动开启 macOS 低电量模式，
并在屏幕解锁后立即恢复正常性能。它主要面向需要长期保持在线、同时又要控制
无人使用时发热和功耗峰值的 Apple 芯片 Mac mini 与 Mac Studio。

## 工作方式

- 锁屏或显示器休眠后，默认等待 120 秒再开启低电量模式。
- 在等待期间解锁，不会开启低电量模式。
- 解锁后立即关闭低电量模式并恢复正常性能。
- 不会让 Mac 进入整机睡眠，也不修改网络唤醒或远程访问设置。
- 不联网、无遥测、没有第三方运行依赖。

## 系统要求

- Apple 芯片 Mac
- macOS Sequoia 15.1 或更高版本
- 安装时使用一次管理员密码

## 安装

```sh
git clone https://github.com/rex2099/LockPower.git
cd LockPower
zsh install.sh
```

指定其他延迟时间，例如锁屏 5 分钟后开启：

```sh
zsh install.sh 300
```

允许设置 1～3600 秒。重复运行安装程序可以升级版本或修改延迟。

## 查看状态

```sh
"$HOME/Library/Application Support/LockPower/status.sh"
```

运行记录保存在 `~/Library/Logs/LockPower.log`。

## 卸载

```sh
"$HOME/Library/Application Support/LockPower/uninstall.sh"
```

卸载会停止后台服务、关闭低电量模式、删除精确限定的管理员授权，并删除安装文件。

## 安全边界

后台进程以当前用户身份运行，不安装特权守护进程或内核扩展。安装程序只允许当前
用户免密码执行以下两条固定命令：

```text
/usr/bin/pmset -a lowpowermode 0
/usr/bin/pmset -a lowpowermode 1
```

授权中没有通配符，不等于开放完整的免密码管理员权限。详情见
[SECURITY.md](SECURITY.md)。

## 许可证

MIT
