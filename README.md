# 蛟龙系列 (Jiaolong 系列) Linux 键盘修复工具

## ⚠️ 警告
* 本脚本专为 **AMD Ryzen 平台蛟龙系列** 设计。
* 涉及底层 ACPI 表修改，**请务必备份数据**。
* 脚本会自动备份 `/etc/default/grub` 到 `/etc/default/grub.bak`。

## 键盘失效原因
- 断代原因：内核 6.0+ 引入补丁 ACPI: skip IRQ override on AMD Zen platforms。
- 冲突点：蛟龙系列 BIOS 将键盘中断（IRQ 1）错误描述为 ActiveLow，而硬件实际为 ActiveHigh。
- 现象：6.0 以前内核会自动“纠错”所以正常；6.0 以后内核选择“信任” BIOS，导致识别错误、键盘失效。
- 唤醒失效：挂起后控制器状态丢失，需强制重置同步。

## 功能
1.  **自动修补 DSDT**：提取当前 ACPI DSDT 表，将键盘中断 (IRQ 1) 的触发极性从 `ActiveLow` 修正为 `ActiveHigh`，并自动增加版本号以强制覆盖。
2.  **生成 CPIO 镜像**：编译并打包为内核可识别的 `acpi_override` 文件。
3.  **配置 GRUB**：
    * 添加 `GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override"` (用于加载补丁)。
    * 添加 `i8042.reset atkbd.reset` (用于修复挂起唤醒失效)。

## 使用方法 (Manjaro/Arch)

1.  赋予脚本执行权限：
    ```bash
    chmod +x fix_kbd.sh
    ```
2.  使用 Root 权限运行：
    ```bash
    sudo ./fix_kbd.sh
    ```
3.  重启系统生效。