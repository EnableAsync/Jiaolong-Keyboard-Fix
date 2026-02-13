#!/bin/bash
set -e

# ================= 配置区 =================
WORK_DIR="/tmp/dsdt_fix_workspace"
BOOT_DIR="/boot"
OVERRIDE_FILE="acpi_override"
GRUB_CFG="/etc/default/grub"
# =========================================

echo "[*] 开始执行蛟龙16K键盘修复流程..."

# 1. 检查 Root 权限
if [ "$EUID" -ne 0 ]; then
  echo "[-] 请使用 sudo 运行此脚本"
  exit 1
fi

# 2. 安装依赖 (仅针对 Arch/Manjaro，其他发行版请手动安装)
echo "[*] 检查依赖..."
if ! command -v iasl &> /dev/null; then
    echo "[-] 未找到 iasl，正在安装 acpica..."
    pacman -S --noconfirm acpica
fi
if ! command -v cpio &> /dev/null; then
    echo "[-] 未找到 cpio，正在安装..."
    pacman -S --noconfirm cpio
fi

# 3. 准备工作目录
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 4. 提取并反编译 DSDT
echo "[*] 提取 DSDT 表..."
cat /sys/firmware/acpi/tables/DSDT > dsdt.dat
iasl -d dsdt.dat > /dev/null

if [ ! -f dsdt.dsl ]; then
    echo "[-] 反编译失败！"
    exit 1
fi

# 5. 修补 DSDT (核心步骤)
echo "[*] 正在修补 DSDT 源码..."

# 5.1 增加 DefinitionBlock 的版本号 (Hex + 1)，确保内核加载
# 逻辑：找到 DefinitionBlock 行，提取最后一个 0x... 数字并加 1
sed -i -r 's/(DefinitionBlock.*)(0x[0-9A-Fa-f]+)(.*\))/"echo \1$(printf "0x%08X" $(( \2 + 1 )))\3"/e' dsdt.dsl

# 5.2 修正键盘 IRQ 极性 (ActiveLow -> ActiveHigh)
# 针对 IRQ 1 (0x00000001) 的特定模式进行替换
# 原始: Interrupt (ResourceConsumer, Edge, ActiveLow, Shared, ,, ) { 0x00000001 }
# 目标: Interrupt (ResourceConsumer, Edge, ActiveHigh, Shared, ,, ) { 0x00000001 }
if grep -q "Interrupt (ResourceConsumer, Edge, ActiveLow, Shared, ,, ) { 0x00000001 }" dsdt.dsl; then
    sed -i 's/Interrupt (ResourceConsumer, Edge, ActiveLow, Shared, ,, ) { 0x00000001 }/Interrupt (ResourceConsumer, Edge, ActiveHigh, Shared, ,, ) { 0x00000001 }/' dsdt.dsl
    echo "[+] 已修正 IRQ 1 极性为 ActiveHigh"
else
    echo "[!] 警告：未找到标准的 ActiveLow IRQ 1 定义，可能已被修改或格式不同。尝试模糊匹配..."
    # 尝试更宽泛的匹配，需谨慎
    sed -i '/Device (KBD)/,/}/ s/ActiveLow/ActiveHigh/g' dsdt.dsl
fi

# 6. 编译并打包
echo "[*] 编译新 DSDT 表..."
iasl -sa dsdt.dsl > /dev/null

echo "[*] 生成 CPIO 归档..."
mkdir -p kernel/firmware/acpi
cp dsdt.aml kernel/firmware/acpi/dsdt.aml
find kernel | cpio -H newc -o > "$OVERRIDE_FILE" 2>/dev/null

# 7. 安装到 /boot
echo "[*] 安装补丁到 $BOOT_DIR..."
cp "$OVERRIDE_FILE" "$BOOT_DIR/$OVERRIDE_FILE"

# 8. 修改 GRUB 配置
echo "[*] 配置 GRUB..."
cp "$GRUB_CFG" "${GRUB_CFG}.bak"
echo "[+] 已备份 GRUB 配置到 ${GRUB_CFG}.bak"

# 8.1 添加 GRUB_EARLY_INITRD_LINUX_CUSTOM
if grep -q "GRUB_EARLY_INITRD_LINUX_CUSTOM" "$GRUB_CFG"; then
    # 如果已存在，替换它
    sed -i "s|^GRUB_EARLY_INITRD_LINUX_CUSTOM=.*|GRUB_EARLY_INITRD_LINUX_CUSTOM=\"$OVERRIDE_FILE\"|" "$GRUB_CFG"
else
    # 如果不存在，追加
    echo "GRUB_EARLY_INITRD_LINUX_CUSTOM=\"$OVERRIDE_FILE\"" >> "$GRUB_CFG"
fi

# 8.2 添加内核参数 (i8042.reset atkbd.reset)
TARGET_PARAMS="i8042.reset atkbd.reset"
CURRENT_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_CFG")

if [[ "$CURRENT_CMDLINE" != *"$TARGET_PARAMS"* ]]; then
    echo "[+] 添加内核参数: $TARGET_PARAMS"
    # 在引号结束前插入参数
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $TARGET_PARAMS\"|" "$GRUB_CFG"
else
    echo "[*] 内核参数已存在，跳过。"
fi

# 9. 更新 GRUB
echo "[*] 更新 GRUB 引导..."
update-grub

echo "============================================"
echo "[√] 完成！请重启电脑以应用更改。"
echo "[!] 注意：如果重启后遇到问题，请在 GRUB 菜单按 'e' 删除相关参数启动。"
echo "============================================"
