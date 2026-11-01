#!/usr/bin/env bash
# 用 SDK 内置的 OpenHarmony 本地签名材料，把 unsigned HAP 签成可分发/可安装的 HAP。
#
# 说明：这里用的是 OpenHarmony 公开测试证书链（SDK tools 里的 OpenHarmony.p12），
# 与 DevEco「自动签名」（需登录华为账号、绑定设备 UDID）是两条不同路径：
#   - 本脚本产物：可在信任 OpenHarmony 测试根的设备/模拟器上安装
#   - 华为商用真机：必须用 DevEco 自动签名（华为签发证书 + 设备 UDID 绑定）
#
# 用法： ./tools/sign_hap.sh [输入.hap] [输出.hap]
set -euo pipefail

DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
LIB="$DEVECO_HOME/sdk/default/openharmony/toolchains/lib"
JAVA="$DEVECO_HOME/jbr/Contents/Home/bin/java"
KEYTOOL="$DEVECO_HOME/jbr/Contents/Home/bin/keytool"
SIGN_TOOL="$LIB/hap-sign-tool.jar"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIG_DIR="$PROJECT_DIR/signature"
DIST_DIR="$PROJECT_DIR/dist"
BUNDLE_NAME="${BUNDLE_NAME:-com.quadrant.todo}"
API_VERSION="${API_VERSION:-20}"

IN_HAP="${1:-$PROJECT_DIR/entry/build/default/outputs/default/entry-default-unsigned.hap}"
OUT_HAP="${2:-$DIST_DIR/quadrant-todo-signed.hap}"

KS="$LIB/OpenHarmony.p12"
KS_PWD="123456"
APP_KEY_ALIAS="openharmony application release"
PROFILE_KEY_ALIAS="openharmony application profile release"
PROFILE_CERT="$LIB/OpenHarmonyProfileRelease.pem"
PROFILE_TEMPLATE="$LIB/UnsgnedReleasedProfileTemplate.json"

[ -f "$IN_HAP" ] || { echo "未找到输入 HAP：$IN_HAP" >&2; exit 1; }
mkdir -p "$SIG_DIR" "$DIST_DIR"

echo "[1/4] 组装应用签名证书链 (Root -> CA -> App)"
APP_CERT="$SIG_DIR/app-release.pem"
if [ ! -f "$APP_CERT" ]; then
  python3 - "$PROFILE_CERT" "$PROFILE_TEMPLATE" "$APP_CERT" <<'PY'
import json, re, sys
pem_src, tpl_src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
certs = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', open(pem_src).read(), re.S)
root, ca = certs[0], certs[1]
leaf = json.load(open(tpl_src))['bundle-info']['distribution-certificate']
leaf = leaf.replace('\\n', '\n')
with open(dst, 'w', encoding='utf-8') as f:
    f.write(root + '\n' + ca + '\n' + leaf + '\n')
print('    证书链已生成，共 3 级')
PY
fi

echo "[2/4] 生成 Provision Profile (bundle: ${BUNDLE_NAME})"
PROFILE_JSON="$SIG_DIR/profile.json"
python3 - "$PROFILE_TEMPLATE" "$PROFILE_JSON" "$BUNDLE_NAME" <<'PY'
import json, sys, time
src, dst, bundle = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, 'r', encoding='utf-8') as f:
    p = json.load(f)
p['bundle-info']['bundle-name'] = bundle
now = int(time.time())
p['validity'] = {'not-before': now - 3600, 'not-after': now + 10 * 365 * 24 * 3600}
p['type'] = 'release'
p['app-distribution-type'] = 'os_integration'
with open(dst, 'w', encoding='utf-8') as f:
    json.dump(p, f, ensure_ascii=False, indent=2)
PY

echo "[3/4] 签名 Profile"
PROFILE_P7B="$SIG_DIR/profile.p7b"
"$JAVA" -jar "$SIGN_TOOL" sign-profile \
  -mode localSign \
  -keyAlias "$PROFILE_KEY_ALIAS" \
  -keyPwd "$KS_PWD" \
  -profileCertFile "$PROFILE_CERT" \
  -inFile "$PROFILE_JSON" \
  -signAlg SHA256withECDSA \
  -keystoreFile "$KS" \
  -keystorePwd "$KS_PWD" \
  -outFile "$PROFILE_P7B"

echo "[4/4] 签名 HAP"
"$JAVA" -jar "$SIGN_TOOL" sign-app \
  -mode localSign \
  -keyAlias "$APP_KEY_ALIAS" \
  -keyPwd "$KS_PWD" \
  -appCertFile "$APP_CERT" \
  -profileFile "$PROFILE_P7B" \
  -profileSigned 1 \
  -inFile "$IN_HAP" \
  -signAlg SHA256withECDSA \
  -keystoreFile "$KS" \
  -keystorePwd "$KS_PWD" \
  -outFile "$OUT_HAP" \
  -compatibleVersion "$API_VERSION" \
  -signCode 1

echo "---- 校验 ----"
"$JAVA" -jar "$SIGN_TOOL" verify-app -inFile "$OUT_HAP" \
  -outCertChain "$DIST_DIR/verify-chain.cer" -outProfile "$DIST_DIR/verify-profile.p7b"

echo "---- 产物 ----"
ls -lh "$DIST_DIR"/*.hap
