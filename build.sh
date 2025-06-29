#!/bin/bash

# 版本过滤参数
TARGET_VERSION="RMX5090_15.0.0.370(CN01)"
if [ "$4" != "${TARGET_VERSION}" ]; then
    echo "错误：仅支持 ${TARGET_VERSION} 版本构建"
    exit 1
fi

# 参数化配置选项
ENABLE_KPM=${1:-false}
ENABLE_LZ4_ZSTD=${2:-true}
ENABLE_WINDDRIVE=${3:-true}

# 克隆内核源码
git clone https://github.com/realme-kernel-opensource/realme_GT7pro-Speed-AndroidV-kernel-source
cd realme_GT7pro-Speed-AndroidV-kernel-source

# 应用基础补丁
curl -s https://raw.githubusercontent.com/showdo/build_oneplus_sm8750/main/hmbird_patch.c | patch -p1

# SUSFS集成（Android 15定制版）
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/dev/kernel/android15_setup.sh" | bash -s susfs-main

# 风驰驱动集成
if [ "$ENABLE_WINDDRIVE" = true ]; then
    git clone -b android15 https://github.com/HanKuCha/sched_ext
    cp -r sched_ext/drivers/misc/winddrive/* drivers/misc/
    echo "CONFIG_WINDDRIVE_V3=y" >> arch/arm64/configs/realme_gt7pro_speed_defconfig
fi

# 编译配置
make O=out realme_gt7pro_speed_defconfig

# KPM配置
if [ "$ENABLE_KPM" = true ]; then
    echo "CONFIG_KPM=y" >> out/.config
fi

# 压缩算法配置
if [ "$ENABLE_LZ4_ZSTD" = true ]; then
    echo "CONFIG_KERNEL_LZ4=y" >> out/.config
    echo "CONFIG_KERNEL_ZSTD=y" >> out/.config
fi

# 编译内核
make -j$(nproc) O=out

# AnyKernel3打包
git clone https://github.com/osm0sis/AnyKernel3
cp out/arch/arm64/boot/Image AnyKernel3/
cd AnyKernel3
zip -r ../realme_gt7pro_speed_kernel-$(date +%Y%m%d).zip *