#!/usr/bin/env bash
# build.sh — 将 qiq-prd2tech skill 打包为 zip。
#
# 用法：
#   ./build.sh                      # 沿用 SKILL.md 当前版本打包，不改动版本号
#   ./build.sh --bump-type patch     # 显式递增 patch 版本并写回 SKILL.md（也可为 minor / major）
#   ./build.sh -o out.zip            # 指定输出文件
#   ./build.sh -v 1.2.0              # 显式指定版本（写回 SKILL.md，不递增）
#   ./build.sh --no-bump             # 兼容保留：显式声明不递增（当前默认行为，等价于不带该参数）
#   ./build.sh --install             # 打包后安装到 ~/.codebuddy/skills/qiq-prd2tech
#   ./build.sh --keep-old            # 保留 dist 目录下的历史 zip（默认会清理，仅保留最新）
#
# 默认包含的内容：
#   SKILL.md
#   references/*.md
#   templates/*.md
#   LICENSE
#
# 打包前自动执行：
#   1. 校验所有必需文件存在
#   2. 校验 SKILL.md 中引用的 references / templates 路径都能找到对应文件
#   3. 反向校验 references/ 与 templates/ 目录下的文件都已纳入打包清单（防止新增文件遗漏）
#   4. 输出文件清单与字节统计
#
# 打包后默认行为：
#   清理 dist/ 目录下旧的 qiq-prd2tech-*.zip，仅保留本次产出的最新 zip。
#   通过 --keep-old 可关闭此清理行为。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="qiq-prd2tech"
SKILL_VERSION=""
BUMP_TYPE=""        # 仅当用户显式传入 --bump-type 时才递增；留空表示不递增
NO_BUMP=true         # 默认沿用当前版本，不递增也不写回 SKILL.md；保留 --no-bump 仅为兼容旧调用

OUTPUT=""
INSTALL=false
KEEP_OLD=false
INSTALL_DIR="${HOME}/.codebuddy/skills/${SKILL_NAME}"

# ---------- 颜色 ----------
if [[ -t 1 ]]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_RESET='\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
fi

log()  { printf "${C_BLUE}[build]${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_GREEN}[ ok ]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW}[warn]${C_RESET} %s\n" "$*"; }
err()  { printf "${C_RED}[err ]${C_RESET} %s\n" "$*" >&2; }

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)    OUTPUT="$2"; shift 2 ;;
        -v|--version)   SKILL_VERSION="$2"; shift 2 ;;
        --bump-type)    BUMP_TYPE="$2"; NO_BUMP=false; shift 2 ;;
        --no-bump)      NO_BUMP=true; shift ;;
        --install)      INSTALL=true; shift ;;
        --keep-old)     KEEP_OLD=true; shift ;;
        -h|--help)    usage ;;
        *) err "未知参数: $1"; exit 1 ;;
    esac
done

# ---------- 进入 skill 根目录 ----------
cd "${SCRIPT_DIR}"

# ---------- 版本号（自动递增 / 显式 / 沿用） ----------
bump_version() {
    local ver="$1" type="$2"
    local major minor patch
    IFS='.' read -r major minor patch <<< "$ver"
    major="${major:-0}"; minor="${minor:-0}"; patch="${patch:-0}"
    case "$type" in
        major)   major=$((major+1)); minor=0; patch=0 ;;
        minor)   minor=$((minor+1)); patch=0 ;;
        patch|*) patch=$((patch+1)) ;;
    esac
    echo "${major}.${minor}.${patch}"
}

if [[ -n "$BUMP_TYPE" && "$BUMP_TYPE" != "patch" && "$BUMP_TYPE" != "minor" && "$BUMP_TYPE" != "major" ]]; then
    err "无效的 --bump-type: $BUMP_TYPE（应为 patch / minor / major）"
    exit 1
fi

CURRENT_VERSION="$(sed -n '/^version:[[:space:]]*/{s/^version:[[:space:]]*//;p;q}' SKILL.md 2>/dev/null || true)"

if [[ -n "$SKILL_VERSION" ]]; then
    :   # -v 显式指定，直接使用（下方写回 SKILL.md）
elif [[ -n "$BUMP_TYPE" ]]; then
    # 仅当用户显式 --bump-type 时才递增并写回
    SKILL_VERSION="$(bump_version "$CURRENT_VERSION" "$BUMP_TYPE")"
else
    # 默认：沿用当前版本，不递增也不写回 SKILL.md
    SKILL_VERSION="$CURRENT_VERSION"
fi

if [[ -n "$SKILL_VERSION" && "$SKILL_VERSION" != "$CURRENT_VERSION" ]]; then
    sed -i.bak -E "s/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+/version: ${SKILL_VERSION}/" SKILL.md
    rm -f SKILL.md.bak
    log "版本号: ${CURRENT_VERSION} -> ${SKILL_VERSION}（已写回 SKILL.md）"
fi

# ---------- 校验必需文件 ----------
log "校验必需文件..."

REQUIRED_FILES=(
    "SKILL.md"
    "LICENSE"
    "references/00-requirements-template.md"
    "references/00b-brief-review-template.md"
    "references/01-requirements-analysis.md"
    "references/02-architecture-overview.md"
    "references/03-detailed-design.md"
    "references/04-key-decisions.md"
    "references/05-availability-fault-tolerance.md"
    "references/06-deployment-operations.md"
    "references/07-risks-open-questions.md"
    "references/08-anti-patterns.md"
    "references/09-quality-gate.md"
    "templates/tech-design.md"
    "templates/brief-design.md"
)

MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        err "缺失文件: $f"
        MISSING=$((MISSING + 1))
    fi
done

if [[ $MISSING -gt 0 ]]; then
    err "共缺失 $MISSING 个文件，构建终止"
    exit 1
fi
ok "所有必需文件齐全（${#REQUIRED_FILES[@]} 个）"

# ---------- 校验 SKILL.md 中的引用路径 ----------
log "校验 SKILL.md 中的引用路径..."
BROKEN=0
# 匹配形如 references/xxx.md 或 templates/xxx.md 的相对路径引用
while IFS= read -r ref; do
    if [[ ! -f "$ref" ]]; then
        err "SKILL.md 引用了不存在的文件: $ref"
        BROKEN=$((BROKEN + 1))
    fi
done < <(grep -oE '(references|templates)/[A-Za-z0-9_./-]+\.md' SKILL.md | sort -u)

if [[ $BROKEN -gt 0 ]]; then
    err "共 $BROKEN 处引用失效，构建终止"
    exit 1
fi
ok "SKILL.md 引用路径全部有效"

# ---------- 反向校验：references/ 与 templates/ 下是否存在未纳入打包清单的文件 ----------
log "反向校验 references/ 与 templates/ 目录下的实际文件是否都在 REQUIRED_FILES 清单中..."
ORPHAN=0
while IFS= read -r -d '' actual_file; do
    rel_path="${actual_file#./}"
    FOUND=false
    for f in "${REQUIRED_FILES[@]}"; do
        if [[ "$f" == "$rel_path" ]]; then
            FOUND=true
            break
        fi
    done
    if [[ "$FOUND" == false ]]; then
        err "发现未纳入 REQUIRED_FILES 打包清单的文件: $rel_path（新增文件请同步加入 build.sh 的 REQUIRED_FILES）"
        ORPHAN=$((ORPHAN + 1))
    fi
done < <(find references templates -maxdepth 1 -type f -name "*.md" -print0)

if [[ $ORPHAN -gt 0 ]]; then
    err "共 $ORPHAN 个文件未纳入打包清单，构建终止"
    exit 1
fi
ok "references/ 与 templates/ 下所有文件均已纳入打包清单"

# ---------- 确定输出路径 ----------
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p dist

if [[ -z "$OUTPUT" ]]; then
    if [[ -n "$SKILL_VERSION" ]]; then
        OUTPUT="dist/${SKILL_NAME}-v${SKILL_VERSION}.zip"
    else
        OUTPUT="dist/${SKILL_NAME}-${TIMESTAMP}.zip"
    fi
fi

# 如果 OUTPUT 是相对路径，转为绝对路径
case "$OUTPUT" in
    /*) ;;
    *)  OUTPUT="${SCRIPT_DIR}/${OUTPUT}" ;;
esac

# 若已存在则覆盖
if [[ -f "$OUTPUT" ]]; then
    warn "输出文件已存在，将覆盖: $OUTPUT"
    rm -f "$OUTPUT"
fi

# ---------- 打包 ----------
if ! command -v zip >/dev/null 2>&1; then
    err "未找到 'zip' 命令，请先安装：apt install zip / brew install zip"
    exit 1
fi

log "打包到: $OUTPUT"

# 使用临时暂存目录，确保 zip 内的顶层目录为 SKILL_NAME
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "${STAGING}/${SKILL_NAME}"
for f in "${REQUIRED_FILES[@]}"; do
    install -D "$f" "${STAGING}/${SKILL_NAME}/$f"
done

# 写入 VERSION.txt
if [[ -n "$SKILL_VERSION" ]]; then
    echo "${SKILL_VERSION}" > "${STAGING}/${SKILL_NAME}/VERSION.txt"
fi

(
    cd "$STAGING"
    zip -qr "$OUTPUT" "$SKILL_NAME" \
        -x "*.DS_Store" "*/.git/*" "*/__pycache__/*"
)

# ---------- 输出统计 ----------
SIZE_BYTES=$(wc -c < "$OUTPUT" | tr -d ' ')
SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$SIZE_BYTES" 2>/dev/null || echo "${SIZE_BYTES}B")

ok "构建完成"
if [[ -n "$SKILL_VERSION" ]]; then
    log "版本: v${SKILL_VERSION}"
fi
log "输出: $OUTPUT"
log "大小: $SIZE_HUMAN ($SIZE_BYTES bytes)"
log "内容清单:"
unzip -l "$OUTPUT" | sed 's/^/      /'

# ---------- 清理 dist 下旧 zip（默认开启，可用 --keep-old 关闭） ----------
DIST_DIR="${SCRIPT_DIR}/dist"
if [[ "$KEEP_OLD" == true ]]; then
    log "保留历史 zip（--keep-old）"
elif [[ -d "$DIST_DIR" ]]; then
    log "清理 dist/ 下的历史 zip（仅保留最新）..."
    REMOVED_COUNT=0
    # 仅清理本 skill 命名规则的 zip，避免误删用户自定义产物
    while IFS= read -r -d '' old_zip; do
        if [[ "$old_zip" != "$OUTPUT" ]]; then
            rm -f -- "$old_zip"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
            log "  已删除：$(basename "$old_zip")"
        fi
    done < <(find "$DIST_DIR" -maxdepth 1 -type f -name "${SKILL_NAME}-*.zip" -print0)
    if [[ $REMOVED_COUNT -eq 0 ]]; then
        ok "无历史 zip 需要清理"
    else
        ok "已清理历史 zip：$REMOVED_COUNT 个，保留：$(basename "$OUTPUT")"
    fi
fi

# ---------- 可选：安装到本地 skills 目录 ----------
if [[ "$INSTALL" == true ]]; then
    log "安装到: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$(dirname "$INSTALL_DIR")"
    cp -r "${STAGING}/${SKILL_NAME}" "$INSTALL_DIR"
    ok "已安装到 $INSTALL_DIR"
fi

ok "全部完成 🎉"
