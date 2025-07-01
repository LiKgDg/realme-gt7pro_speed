#!/bin/bash

# realme GT7 Pro 内核本地构建脚本 (Ubuntu 25.04环境优化)
# 适用于Ubuntu 25.04，修复外部管理环境问题和GCC兼容性

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 恢复默认

# 检查命令是否存在
check_command() {
  if ! command -v $1 &> /dev/null; then
    echo -e "${RED}错误: 未找到 $1 命令，请先安装${NC}"
    exit 1
  fi
}

# 配置编译环境
configure_build_environment() {
  echo -e "${YELLOW}正在配置编译环境...${NC}"
  
  # 检查并设置GCC版本
  GCC_VERSION=$(gcc --version | head -n1 | grep -oP '\d+\.\d+')
  if (( $(echo "$GCC_VERSION >= 13.0" | bc -l) )); then
    echo -e "${YELLOW}检测到GCC版本 >= 13.0，设置兼容选项${NC}"
    export CFLAGS="-Wno-error=stringop-overflow -Wno-error=implicit-fallthrough"
    export CXXFLAGS="$CFLAGS"
  fi
  
  # 设置编译线程数
  export MAKEFLAGS="-j$(nproc)"
  
  echo -e "${GREEN}编译环境配置完成${NC}"
}

# 安装依赖
install_dependencies() {
  echo -e "${YELLOW}正在安装编译依赖...${NC}"
  
  # 更新包索引
  sudo apt-get update
  
  # 安装基础编译工具
  sudo apt-get install -y build-essential bc bison flex libssl-dev patch
  
  # 安装交叉编译工具链
  read -p "请输入架构 (arm64/x86_64，默认arm64): " ARCH
  ARCH=${ARCH:-"arm64"}
  
  if [ "$ARCH" == "arm64" ]; then
    sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
  else
    sudo apt-get install -y gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu
  fi
  
  # 安装Bazel构建工具
  echo -e "${YELLOW}正在安装Bazel构建工具...${NC}"
  sudo apt-get install -y apt-transport-https curl gnupg
  curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > bazel.gpg
  sudo mv bazel.gpg /etc/apt/trusted.gpg.d/
  echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
  sudo apt-get update
  sudo apt-get install -y bazel-5.4.1
  sudo ln -s /usr/bin/bazel-5.4.1 /usr/bin/bazel
  
  # 安装Python环境和依赖
  echo -e "${YELLOW}正在配置Python环境...${NC}"
  sudo apt-get install -y python3-full python3-venv python3-pip
  
  # 创建并激活虚拟环境
  python3 -m venv ~/kernel_build_venv
  source ~/kernel_build_venv/bin/activate
  
  # 在虚拟环境中安装Python包
  pip install numpy==1.23.5 six==1.16.0 protobuf==3.20.3 wheel
  
  # 保存虚拟环境路径到环境变量
  echo "export KERNEL_VENV=~/kernel_build_venv" >> ~/.bashrc
  source ~/.bashrc
  
  echo -e "${GREEN}依赖安装完成${NC}"
}

# 初始化源码
init_source() {
  echo -e "${YELLOW}正在初始化源码...${NC}"
  if [ ! -d "kernel" ]; then
    echo -e "${YELLOW}未检测到kernel目录，是否克隆realme GT7 Pro内核源码? (y/n)${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo -e "${RED}请先将内核源码克隆到当前目录下的kernel文件夹${NC}"
      exit 1
    fi
    # 这里需要用户自行克隆源码，示例：
    echo -e "${YELLOW}请克隆realme GT7 Pro内核源码到当前目录的kernel文件夹:${NC}"
    echo "git clone <源码仓库地址> kernel"
    echo "cd kernel && git submodule update --init --recursive"
    exit 0
  fi
  
  cd kernel
  git submodule update --init --recursive
  cd ..
  echo -e "${GREEN}源码初始化完成${NC}"
}

# 集成SukiSU
integrate_sukisu() {
  echo -e "${YELLOW}正在集成SukiSU Ultra...${NC}"
  read -p "是否启用SukiSU Ultra? (true/false，默认true): " ENABLE_SUKISU
  ENABLE_SUKISU=${ENABLE_SUKISU:-"true"}
  
  if [ "$ENABLE_SUKISU" == "true" ]; then
    read -p "GKI模式? (true/false，默认true): " GKI_MODE
    GKI_MODE=${GKI_MODE:-"true"}
    
    mkdir -p sukisutemp
    cd sukisutemp
    
    # 三镜像源下载setup.sh
    SUCCESS=false
    for URL in "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
               "https://gitee.com/mirrors/SukiSU-Ultra/raw/main/kernel/setup.sh" \
               "https://hub.fastgit.xyz/SukiSU-Ultra/SukiSU-Ultra/raw/main/kernel/setup.sh"; do
      if curl -LSs -o setup.sh $URL; then
        SUCCESS=true
        break
      fi
    done
    
    if [ "$SUCCESS" == "false" ]; then
      echo -e "${RED}SukiSU脚本下载失败，请手动下载后放入sukisutemp目录${NC}"
      exit 1
    fi
    
    chmod +x setup.sh
    echo "开始集成SukiSU Ultra，GKI模式: $GKI_MODE"
    
    if [ "$GKI_MODE" == "true" ]; then
      ./setup.sh main || { echo -e "${RED}main分支集成失败${NC}"; exit 1; }
    else
      ./setup.sh nongki || { echo -e "${RED}nongki分支集成失败${NC}"; exit 1; }
    fi
    
    # 自动部署补丁
    mkdir -p kernel/patches
    if [ "$GKI_MODE" == "true" ]; then
      PATCH_URL="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/patches/0001-Add-KSU-hooks-for-GKI.patch"
      PATCH_FILE="kernel/patches/0001-Add-KSU-hooks-for-GKI.patch"
    else
      PATCH_URL="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/patches/0001-Add-KSU-hooks-for-nongki.patch"
      PATCH_FILE="kernel/patches/0001-Add-KSU-hooks-for-nongki.patch"
    fi
    
    if [ ! -f $PATCH_FILE ]; then
      for URL in $PATCH_URL "https://gitee.com/mirrors/SukiSU-Ultra/raw/main/kernel/patches/0001-Add-KSU-hooks-for-GKI.patch" "https://hub.fastgit.xyz/SukiSU-Ultra/SukiSU-Ultra/raw/main/kernel/patches/0001-Add-KSU-hooks-for-GKI.patch"; do
        if curl -LSs $URL -o $PATCH_FILE; then
          chmod +x $PATCH_FILE
          echo "已从镜像下载补丁: $PATCH_FILE"
          break
        fi
      done
    fi
    
    if [ ! -f $PATCH_FILE ]; then
      echo -e "${RED}补丁文件下载失败，请手动下载后放入kernel/patches目录${NC}"
      exit 1
    fi
    
    patch -p1 < $PATCH_FILE || { echo -e "${RED}补丁应用失败${NC}"; exit 1; }
    
    cp -r kernel/* ..
    cd ..
    rm -rf sukisutemp
    echo -e "${GREEN}SukiSU集成完成${NC}"
  else
    echo "跳过SukiSU集成"
  fi
}

# 配置内核
configure_kernel() {
  echo -e "${YELLOW}正在配置内核...${NC}"
  cd kernel
  
  read -p "内核版本 (如: 6.6，默认6.6): " KERNEL_VERSION
  KERNEL_VERSION=${KERNEL_VERSION:-"6.6"}
  
  read -p "GKI模式? (true/false，默认true): " GKI_MODE
  GKI_MODE=${GKI_MODE:-"true"}
  
  read -p "启用SuSFS? (true/false，默认true): " ENABLE_SUSFS
  ENABLE_SUSFS=${ENABLE_SUSFS:-"true"}
  
  read -p "启用ZRAM? (true/false，默认true): " ENABLE_ZRAM
  ENABLE_ZRAM=${ENABLE_ZRAM:-"true"}
  
  read -p "ZRAM算法 (逗号分隔，如: lz4,lzo，默认lz4,lzo): " ZRAM_ALGORITHMS
  ZRAM_ALGORITHMS=${ZRAM_ALGORITHMS:-"lz4,lzo"}
  
  read -p "启用KPM? (true/false，默认true): " ENABLE_KPM
  ENABLE_KPM=${ENABLE_KPM:-"true"}
  
  read -p "启用BBR? (true/false，默认true): " ENABLE_BBR
  ENABLE_BBR=${ENABLE_BBR:-"true"}
  
  make ARCH=$ARCH mrproper
  
  if [ "$GKI_MODE" == "true" ]; then
    if [ "$ARCH" == "arm64" ]; then
      REALME_PLATFORM="msm.sun"
      make ARCH=arm64 $REALME_PLATFORM_defconfig
      echo "已加载 $REALME_PLATFORM_defconfig"
      
      GKI_CONFIG=build.config.gki.aarch64
      if [ ! -f $GKI_CONFIG ] || [ $(grep -c "CONFIG_KSU=y" $GKI_CONFIG) -eq 0 ] || [ $(wc -l < $GKI_CONFIG) -lt 100 ] || [ $(grep -c "CONFIG_GKI=y" $GKI_CONFIG) -eq 0 ]; then
        make ARCH=arm64 $REALME_PLATFORM-gki_defconfig
        echo "CONFIG_KSU=y" >> .config
        echo "CONFIG_KPROBES=y" >> .config
        echo "CONFIG_GKI=y" >> .config
        cp .config $GKI_CONFIG
        echo "已生成并强化GKI配置文件"
      fi
      
      cp $GKI_CONFIG kernel/$GKI_CONFIG
      chmod +r kernel/$GKI_CONFIG
      cp $GKI_CONFIG .config
    else
      make ARCH=x86_64 gki_x86_64_defconfig
    fi
  else
    if [ "$ARCH" == "arm64" ]; then
      make ARCH=arm64 allmodconfig
    else
      make ARCH=x86_64 allmodconfig
    fi
  fi
  
  if [ "$ENABLE_SUKISU" == "true" ]; then
    echo "CONFIG_KSU=y" >> .config
    if [ "$GKI_MODE" == "true" ]; then
      echo "CONFIG_KPROBES=y" >> .config
    else
      echo "CONFIG_KSU_MANUAL_HOOK=y" >> .config
    fi
  fi
  
  if [ "$ENABLE_SUSFS" == "true" ]; then
    if [ "$ENABLE_SUKISU" == "true" ]; then
      echo "SukiSU已集成SuSFS，跳过单独配置"
    else
      echo "CONFIG_SUSFS=y" >> .config
      echo "CONFIG_SUSFS_FS=y" >> .config
    fi
  fi
  
  if [ "$ENABLE_ZRAM" == "true" ]; then
    echo "CONFIG_ZRAM=y" >> .config
    echo "CONFIG_ZRAM_STATS=y" >> .config
    for alg in ${ZRAM_ALGORITHMS//,/ }; do
      echo "CONFIG_ZRAM_$alg=y" >> .config
    done
  fi
  
  if [ "$ENABLE_KPM" == "true" ]; then
    echo "CONFIG_KPM=y" >> .config
    echo "CONFIG_KALLSYMS=y" >> .config
    echo "CONFIG_KALLSYMS_ALL=y" >> .config
  fi
  
  if [ "$ENABLE_BBR" == "true" ]; then
    echo "CONFIG_TCP_BBR=y" >> .config
    echo "CONFIG_NET_EMU=y" >> .config
  fi
  
  make ARCH=$ARCH savedefconfig
  if [ ! -f defconfig ]; then
    echo -e "${RED}配置保存失败，检查是否有语法错误${NC}"
    exit 1
  fi
  cp defconfig .config
  
  echo "==== 关键配置 ===="
  grep -E "KSU|SUSFS|ZRAM|KPM|TCP_BBR|GKI" .config
  
  cd ..
  echo -e "${GREEN}内核配置完成${NC}"
}

# 编译内核
compile_kernel() {
  echo -e "${YELLOW}正在编译内核...${NC}"
  cd kernel
  
  # 激活虚拟环境
  source $KERNEL_VENV/bin/activate
  
  export BAZEL_VS=16
  export PATH=$PATH:/usr/bin:/usr/local/bin
  
  bazel version
  
  if [ "$GKI_MODE" == "true" ] && [ "$ARCH" == "arm64" ]; then
    export KERNEL_CONFIG=build.config.gki.aarch64
    echo "使用GKI配置: $KERNEL_CONFIG"
    
    # 强制更新BUILD.bazel路径
    if grep -q "config_path" BUILD.bazel; then
      sed -i "s|config_path = \"\(.*\)\"|config_path = \"$KERNEL_CONFIG\"|" BUILD.bazel
    else
      echo "config_path = \"$KERNEL_CONFIG\"" >> BUILD.bazel
    fi
    
    CONFIG_PATH=$(grep "config_path" BUILD.bazel | awk -F\" '{print $2}')
    if [ "$CONFIG_PATH" != "$KERNEL_CONFIG" ]; then
      echo -e "${RED}BUILD.bazel路径更新失败，请手动修改${NC}"
      exit 1
    fi
  fi
  
  if [ "$ARCH" == "arm64" ]; then
    if [ "$GKI_MODE" == "true" ]; then
      python3 build_with_bazel.py --arch=arm64 --config=gki || python3 build_with_bazel.py --arch=arm64 --config=gki
    else
      python3 build_with_bazel.py --arch=arm64 --config=allmodconfig || python3 build_with_bazel.py --arch=arm64 --config=allmodconfig
    fi
  else
    if [ "$GKI_MODE" == "true" ]; then
      python3 build_with_bazel.py --arch=x86_64 --config=gki || python3 build_with_bazel.py --arch=x86_64 --config=gki
    else
      python3 build_with_bazel.py --arch=x86_64 --config=allmodconfig || python3 build_with_bazel.py --arch=x86_64 --config=allmodconfig
    fi
  fi
  
  make ARCH=$ARCH modules -j$(nproc)
  
  cd ..
  echo -e "${GREEN}内核编译完成${NC}"
}

# 打包产物
package_kernel() {
  echo -e "${YELLOW}正在打包内核产物...${NC}"
  mkdir -p output
  
  cd kernel
  
  if [ "$ARCH" == "arm64" ]; then
    if [ "$GKI_MODE" == "true" ]; then
      if [ ! -f bazel-out/arm64-Release/obj/kernel/arch/arm64/boot/Image ]; then
        echo -e "${RED}GKI内核镜像未生成，请检查编译日志${NC}"
        ls -la bazel-out/arm64-Release/obj/kernel/arch/arm64/boot/
        exit 1
      fi
      cp bazel-out/arm64-Release/obj/kernel/arch/arm64/boot/Image ../output/Image-gki
    else
      if [ ! -f arch/arm64/boot/Image ]; then
        echo -e "${RED}非GKI内核镜像未生成，请检查编译日志${NC}"
        ls -la arch/arm64/boot/
        exit 1
      fi
      cp arch/arm64/boot/Image ../output/Image
    fi
  else
    if [ "$GKI_MODE" == "true" ]; then
      if [ ! -f bazel-out/x86_64-Release/obj/kernel/arch/x86/boot/bzImage ]; then
        echo -e "${RED}GKI内核镜像未生成，请检查编译日志${NC}"
        ls -la bazel-out/x86_64-Release/obj/kernel/arch/x86/boot/
        exit 1
      fi
      cp bazel-out/x86_64-Release/obj/kernel/arch/x86/boot/bzImage ../output/bzImage-gki
    else
      if [ ! -f arch/x86/boot/bzImage ]; then
        echo -e "${RED}非GKI内核镜像未生成，请检查编译日志${NC}"
        ls -la arch/x86/boot/
        exit 1
      fi
      cp arch/x86/boot/bzImage ../output/bzImage
    fi
  fi
  
  mkdir -p ../output/modules
  make ARCH=$ARCH INSTALL_MOD_PATH=../output/modules modules_install
  
  mkdir -p ../output/AnyKernel3
  if [ -d "scripts/anykernel3_template" ]; then
    cp -r scripts/anykernel3_template ../output/AnyKernel3/
  else
    echo -e "${YELLOW}未找到AnyKernel3模板，使用简化模板${NC}"
    mkdir -p ../output/AnyKernel3/{boot,system,vendor}
    echo "#!/bin/sh" > ../output/AnyKernel3/flash.sh
    echo "echo \"No flash script available\"" >> ../output/AnyKernel3/flash.sh
    chmod +x ../output/AnyKernel3/flash.sh
  fi
  
  cd ../output/AnyKernel3
  if [ "$ARCH" == "arm64" ]; then
    if [ "$GKI_MODE" == "true" ]; then
      cp ../../kernel/Image-gki zImage
    else
      cp ../../kernel/Image zImage
    fi
  else
    if [ "$GKI_MODE" == "true" ]; then
      cp ../../kernel/bzImage-gki zImage
    else
      cp ../../kernel/bzImage zImage
    fi
  fi
  
  if [ -f flash.sh ]; then
    sed -i "s/KERNEL_VERSION/$KERNEL_VERSION/g" flash.sh
    sed -i "s/ARCHITECTURE/$ARCH/g" flash.sh
  fi
  
  cd ..
  if [ "$ARCH" == "arm64" ]; then
    if [ "$GKI_MODE" == "true" ]; then
      tar -czvf realme-gt7pro-gki-arm64-${KERNEL_VERSION}.tar.gz AnyKernel3
    else
      tar -czvf realme-gt7pro-arm64-${KERNEL_VERSION}.tar.gz AnyKernel3
    fi
  else
    if [ "$GKI_MODE" == "true" ]; then
      tar -czvf realme-gt7pro-gki-x86_64-${KERNEL_VERSION}.tar.gz AnyKernel3
    else
      tar -czvf realme-gt7pro-x86_64-${KERNEL_VERSION}.tar.gz AnyKernel3
    fi
  fi
  
  echo "==== 打包完成 ===="
  ls -la output/
  
  echo -e "${GREEN}内核构建完成，产物位于output目录${NC}"
}

# 主函数
main() {
  echo -e "${GREEN}==== realme GT7 Pro 内核本地构建脚本 ====${NC}"
  
  # 检查必要命令
  check_command git
  check_command curl
  check_command make
  check_command bazel
  
  install_dependencies
  configure_build_environment  # 新增环境配置步骤
  init_source
  integrate_sukisu
  configure_kernel
  compile_kernel
  package_kernel
}

# 执行主函数
main