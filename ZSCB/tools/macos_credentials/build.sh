#!/bin/sh
set -eu
cd "$(dirname "$0")"
xcrun clang -fobjc-arc -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 -Wall -Wextra -Wno-deprecated-declarations -framework Security -framework Foundation client.m -o zhijian-credential
/usr/bin/codesign --force --sign - --identifier com.zhijian.paper-castle.credentials.v1 zhijian-credential
/usr/bin/codesign --verify --strict zhijian-credential
/usr/bin/shasum -a 256 zhijian-credential
