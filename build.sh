#!/bin/bash

# BICurlDownloader XCFramework Build Script
# Собирает фреймворк для всех поддерживаемых платформ iOS

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
FRAMEWORK_NAME="BICurlDownloader"
PROJECT_NAME="BICurlDownloader.xcodeproj"
SCHEME_NAME="BICurlDownloader"
BUILD_DIR="Build"
RESULT_DIR="Result"
XCFRAMEWORK_NAME="${FRAMEWORK_NAME}.xcframework"

# Путь к корню проекта (где находится скрипт)
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Building ${FRAMEWORK_NAME} XCFramework${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Проверка наличия проекта
if [ ! -d "${PROJECT_NAME}" ]; then
    echo -e "${RED}Error: Project ${PROJECT_NAME} not found!${NC}"
    exit 1
fi

# Проверка наличия curl.xcframework
CURL_FRAMEWORK_PATH="BICurlDownloader/External/curl-ios/curl.xcframework"
if [ ! -d "${CURL_FRAMEWORK_PATH}" ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}ERROR: curl.xcframework not found!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Before building BICurlDownloader, you need to build curl.xcframework:${NC}"
    echo ""
    echo -e "${BLUE}1. Clone the curl-ios repository:${NC}"
    echo -e "   cd /path/to/workspace"
    echo -e "   git clone https://github.com/tls-inspector/curl-ios.git"
    echo -e "   cd curl-ios"
    echo ""
    echo -e "${BLUE}2. Build curl.xcframework:${NC}"
    echo -e "   chmod +x build-ios.sh"
    echo -e "   ./build-ios.sh"
    echo ""
    echo -e "${BLUE}3. Copy to BICurlDownloader:${NC}"
    echo -e "   cp -R curl.xcframework $(pwd)/BICurlDownloader/External/curl-ios/"
    echo ""
    echo -e "${YELLOW}For more details, see BUILD_INSTRUCTIONS.md${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ curl.xcframework found${NC}"

# Показываем информацию о сборке
echo -e "${BLUE}Build Configuration:${NC}"
echo -e "  Project: ${PROJECT_NAME}"
echo -e "  Scheme: ${SCHEME_NAME}"
echo -e "  curl.xcframework: ${GREEN}✓ Found${NC}"
echo ""

# Очистка предыдущих сборок
echo -e "${YELLOW}Cleaning previous builds...${NC}"
rm -rf "${BUILD_DIR}"
rm -rf "${RESULT_DIR}"

# Создание директорий
mkdir -p "${BUILD_DIR}"
mkdir -p "${RESULT_DIR}"

echo -e "${GREEN}✓ Directories prepared${NC}"
echo ""

# Функция для сборки фреймворка
build_framework() {
    local PLATFORM=$1
    local SDK=$2
    local DESTINATION=$3
    local BUILD_PATH="${BUILD_DIR}/${PLATFORM}"
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Building for ${PLATFORM}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    xcodebuild archive \
        -project "${PROJECT_NAME}" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -destination "${DESTINATION}" \
        -archivePath "${BUILD_PATH}" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ONLY_ACTIVE_ARCH=NO \
        ARCHS="${SDK}" \
        VALID_ARCHS="${SDK}" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO 2>&1 | tee "${BUILD_DIR}/${PLATFORM}-build.log"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully built for ${PLATFORM}${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Failed to build for ${PLATFORM}${NC}"
        echo -e "${YELLOW}Check log: ${BUILD_DIR}/${PLATFORM}-build.log${NC}"
        return 1
    fi
}

# Сборка для iOS устройств (arm64)
echo -e "${YELLOW}Step 1/3: Building for iOS Device (arm64)...${NC}"
echo ""
build_framework "iOS" "arm64" "generic/platform=iOS" || {
    echo -e "${RED}Failed to build for iOS Device${NC}"
    echo -e "${YELLOW}Trying alternative build method...${NC}"
    
    xcodebuild build \
        -project "${PROJECT_NAME}" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -sdk iphoneos \
        -arch arm64 \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        CONFIGURATION_BUILD_DIR="${BUILD_DIR}/iOS-build" 2>&1 | tee "${BUILD_DIR}/iOS-build-alternative.log"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        # Создаем структуру архива вручную
        mkdir -p "${BUILD_DIR}/iOS.xcarchive/Products/Library/Frameworks"
        cp -R "${BUILD_DIR}/iOS-build/${FRAMEWORK_NAME}.framework" "${BUILD_DIR}/iOS.xcarchive/Products/Library/Frameworks/"
        echo -e "${GREEN}✓ iOS Device build successful (alternative method)${NC}"
    else
        echo -e "${RED}Both build methods failed for iOS Device${NC}"
        exit 1
    fi
}

# Сборка для iOS симулятора (x86_64 + arm64)
echo -e "${YELLOW}Step 2/3: Building for iOS Simulator (x86_64 + arm64)...${NC}"
echo ""
build_framework "iOS-Simulator" "x86_64 arm64" "generic/platform=iOS Simulator" || {
    echo -e "${YELLOW}Trying alternative build method for Simulator...${NC}"
    
    xcodebuild build \
        -project "${PROJECT_NAME}" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -sdk iphonesimulator \
        -arch "x86_64" -arch "arm64" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        CONFIGURATION_BUILD_DIR="${BUILD_DIR}/Simulator-build" 2>&1 | tee "${BUILD_DIR}/Simulator-build-alternative.log"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        mkdir -p "${BUILD_DIR}/iOS-Simulator.xcarchive/Products/Library/Frameworks"
        cp -R "${BUILD_DIR}/Simulator-build/${FRAMEWORK_NAME}.framework" "${BUILD_DIR}/iOS-Simulator.xcarchive/Products/Library/Frameworks/"
        echo -e "${GREEN}✓ iOS Simulator build successful (alternative method)${NC}"
    else
        echo -e "${RED}Both build methods failed for iOS Simulator${NC}"
        exit 1
    fi
}

# Создание XCFramework
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Step 3/3: Creating XCFramework...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

FRAMEWORK_IOS="${BUILD_DIR}/iOS.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework"
FRAMEWORK_SIMULATOR="${BUILD_DIR}/iOS-Simulator.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework"

# Проверка наличия фреймворков
if [ ! -d "${FRAMEWORK_IOS}" ]; then
    echo -e "${RED}Error: iOS framework not found at ${FRAMEWORK_IOS}${NC}"
    echo -e "${YELLOW}Looking for alternative locations...${NC}"
    find "${BUILD_DIR}" -name "${FRAMEWORK_NAME}.framework" -type d
    exit 1
fi

if [ ! -d "${FRAMEWORK_SIMULATOR}" ]; then
    echo -e "${RED}Error: Simulator framework not found at ${FRAMEWORK_SIMULATOR}${NC}"
    echo -e "${YELLOW}Looking for alternative locations...${NC}"
    find "${BUILD_DIR}" -name "${FRAMEWORK_NAME}.framework" -type d
    exit 1
fi

echo -e "${BLUE}Creating XCFramework from:${NC}"
echo -e "  iOS: ${FRAMEWORK_IOS}"
echo -e "  Simulator: ${FRAMEWORK_SIMULATOR}"
echo ""

xcodebuild -create-xcframework \
    -framework "${FRAMEWORK_IOS}" \
    -framework "${FRAMEWORK_SIMULATOR}" \
    -output "${RESULT_DIR}/${XCFRAMEWORK_NAME}"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}XCFramework location:${NC} ${GREEN}${RESULT_DIR}/${XCFRAMEWORK_NAME}${NC}"
    
    # Показываем информацию о XCFramework
    echo ""
    echo -e "${BLUE}Supported platforms:${NC}"
    find "${RESULT_DIR}/${XCFRAMEWORK_NAME}" -name "*.framework" | while read framework; do
        platform=$(basename $(dirname $framework))
        echo -e "  ${GREEN}✓${NC} $platform"
    done
    
    # Размер
    if command -v du &> /dev/null; then
        XCFRAMEWORK_SIZE=$(du -sh "${RESULT_DIR}/${XCFRAMEWORK_NAME}" | cut -f1)
        echo ""
        echo -e "${BLUE}Size:${NC} ${XCFRAMEWORK_SIZE}"
    fi
    
    echo ""
    echo -e "${GREEN}You can now integrate this XCFramework into your projects!${NC}"
    echo -e "${BLUE}Location:${NC} $(pwd)/${RESULT_DIR}/${XCFRAMEWORK_NAME}"
else
    echo -e "${RED}Failed to create XCFramework${NC}"
    exit 1
fi

# Опционально: очистка промежуточных файлов
echo ""
read -p "$(echo -e ${YELLOW}Clean build artifacts? [y/N]:${NC} )" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleaning build artifacts...${NC}"
    rm -rf "${BUILD_DIR}"
    echo -e "${GREEN}✓ Cleaned${NC}"
fi

echo ""
echo -e "${GREEN}Done! 🎉${NC}"
