#!/bin/sh

while getopts v:p:dh OPTION
do 
    case "${OPTION}"
        in
        v) INPUT=${OPTARG};;
        p) PAGE_SIZE=${OPTARG};;
        d) DEBUG="true"
           echo "DEBUG mode is ON"
           ;;
        h|?)
            echo "
        Usage: 
            
            $(basename "$0") [-v <version_comma_separated> ] [-p <page_size_integer_value> ] [-d]

            -d: debug. If flag is used, debug mode is ON and prints the curl commands executed.
            -v: version to test. Ex: v1.31.6-rc1+rke2r1,v1.31.6-rc1+k3s1,v1.31.5+rke2r1
            -p: page size for curl commands to fetch data from docker hub or github. Default is 200.
            -h: help - usage is displayed
            "
            exit 1
            ;;
        esac
done

# Set defaults if not provided
if [ -z "${INPUT}" ]; then
    echo "Please provide the version to test using -v option."
    exit 1
fi
if [ -z "${DEBUG}" ]; then
    DEBUG="false"
fi
if [ -z "${PAGE_SIZE}" ]; then
    PAGE_SIZE=200
fi

debug_log () {
    if [ "${DEBUG}" = true ]; then
        echo "$ $1"
    fi
}

verify_count () {
    # $1 count $2 expected_count $3 log item we are checking
    COUNT="$1"
    EXPECTED_COUNT="$2"
    DESCRIPTION="$3"

    if [ "${COUNT}" -eq "${EXPECTED_COUNT}" ] || [ "${COUNT}" -gt "${EXPECTED_COUNT}" ]; then
        echo "PASS: ${DESCRIPTION} Count is ${COUNT}."
    else
        echo "FAIL: Not found enough ${DESCRIPTION}. Expected count ${EXPECTED_COUNT} but got ${COUNT}."
    fi
}

verify_system_agent_installers () {
    # $1 product $2 version_prefix (Ex: v1.31.2-rc4) $3 version_suffix (Ex: rke2r1 or k3s1)
    PRDT="$1"
    V_PREFIX="$2"
    V_SUFFIX="$3"

    SAI_OUTPUT_FILE="sys_agent_installers_${RANDOM}"
    SYSTEM_AGENT_INSTALLER_URL="https://registry.hub.docker.com/v2/repositories/rancher/system-agent-installer-${PRDT}/tags?page_size=${PAGE_SIZE}"
    
    echo "\n==== VERIFY SYSTEM AGENT INSTALLER FOR prdt: ${PRDT} version prefix: ${V_PREFIX}  version suffix: ${V_SUFFIX}: ===="

    if echo "${V_PREFIX}" | grep -q "rc"; then
        debug_log "curl -L -s \"${SYSTEM_AGENT_INSTALLER_URL}\" | jq -r \".results[].name\" | grep ${V_PREFIX} | grep ${V_SUFFIX} | tee -a \"${SAI_OUTPUT_FILE}\""
        curl -L -s "${SYSTEM_AGENT_INSTALLER_URL}" | jq -r ".results[].name" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | tee -a "${SAI_OUTPUT_FILE}"
    else
        debug_log "curl -L -s \"${SYSTEM_AGENT_INSTALLER_URL}\" | jq -r \".results[].name\" | grep ${V_PREFIX} | grep ${V_SUFFIX} | grep -v \"rc\" | tee -a \"${SAI_OUTPUT_FILE}\""
        curl -L -s "${SYSTEM_AGENT_INSTALLER_URL}" | jq -r ".results[].name" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | grep -v "rc" | tee -a "${SAI_OUTPUT_FILE}"
    fi

    SAI_COUNT=$(cat "${SAI_OUTPUT_FILE}" | wc -l)
    WINDOWS_COUNT=$(cat "${SAI_OUTPUT_FILE}" | grep "windows" | wc -l)
    LINUX_ARM_COUNT=$(cat "${SAI_OUTPUT_FILE}" | grep "linux-arm64" | wc -l)
    LINUX_AMD_COUNT=$(cat "${SAI_OUTPUT_FILE}" | grep "linux-amd64" | wc -l)
    
    if [ "${PRDT}" = "rke2" ]; then
        verify_count "${SAI_COUNT}" "5" "Total images"
        verify_count "${WINDOWS_COUNT}" "2" "Windows images"
    else
        verify_count "${SAI_COUNT}" "3" "Total images"
    fi

    verify_count "${LINUX_ARM_COUNT}" "1" "Linux arm images"
    verify_count "${LINUX_AMD_COUNT}" "1" "linux-amd64 images"

    rm -rf "${SAI_OUTPUT_FILE}"
}

verify_upgrade_images () {
    # $1 product $2 version_prefix (Ex: v1.31.2-rc4) $3 version_suffix (Ex: rke2r1 or k3s1)
    PRDT="$1"
    V_PREFIX="$2"
    V_SUFFIX="$3"

    UPG_OUTPUT_FILE="upgrade_images_${RANDOM}"
    UPGRADE_IMAGES_URL="https://registry.hub.docker.com/v2/repositories/rancher/${PRDT}-upgrade/tags?page_size=${PAGE_SIZE}"
    
    echo "\n==== VERIFY UPGRADE IMAGES FOR ${PRDT} ${V_PREFIX}: ===="

    if echo $2 | grep -q "rc"; then
        debug_log "curl -L -s ${UPGRADE_IMAGES_URL} | jq -r \".results[].name\" | grep ${V_PREFIX} | grep "${V_SUFFIX}""
        curl -L -s "${UPGRADE_IMAGES_URL}" | jq -r ".results[].name" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | tee -a "${UPG_OUTPUT_FILE}"
    else
        debug_log "curl -L -s ${UPGRADE_IMAGES_URL} | jq -r \".results[].name\" | grep ${V_PREFIX} | grep "${V_SUFFIX}" | grep -v \"rc\""
        curl -L -s "${UPGRADE_IMAGES_URL}" | jq -r ".results[].name" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | grep -v "rc" | tee -a "${UPG_OUTPUT_FILE}"
    fi
    
    UPGRADE_COUNT=$(cat "${UPG_OUTPUT_FILE}" | wc -l)
    verify_count "${UPGRADE_COUNT}" "1" "Upgrade images"
    
    rm -rf "${UPG_OUTPUT_FILE}"
}

verify_releases () {
    # useless unless we can check on the asset count.
    # $1 product $2 version_prefix (Ex: v1.31.2-rc4) $3 version_suffix (Ex: rke2r1 or k3s1)
    PRDT="$1"
    V_PREFIX="$2"
    V_SUFFIX="$3"

    RELEASES_FILE="releases_${RANDOM}"
    
    echo "\n==== VERIFY RELEASES FOR ${PRDT} ${V_PREFIX} ${V_SUFFIX}: ===="

    if [ "${PRDT}" = "rke2" ]; then
        RELEASES_URL="https://api.github.com/repos/rancher/rke2/releases"
    else
        RELEASES_URL="https://api.github.com/repos/k3s-io/k3s/releases"
    fi

    if echo "${V_PREFIX}" | grep -q "rc"; then
        debug_log "curl -s -H \"Accept: application/vnd.github+json\" ${RELEASES_URL} | jq '.[].tag_name' | grep ${V_PREFIX} | grep ${V_SUFFIX}"
        curl -s -H "Accept: application/vnd.github+json" "${RELEASES_URL}" | jq '.[].tag_name' | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | tee -a "${RELEASES_FILE}"
    else
        debug_log "curl -s -H \"Accept: application/vnd.github+json\" ${RELEASES_URL} | jq '.[].tag_name' | grep ${V_PREFIX} | grep ${V_SUFFIX} | grep -v \"rc\""
        curl -s -H "Accept: application/vnd.github+json" "${RELEASES_URL}" | jq '.[].tag_name' | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | grep -v "rc" | tee -a "${RELEASES_FILE}"
    fi

    RELEASES_COUNT=$(cat "${RELEASES_FILE}" | wc -l)
    verify_count "${RELEASES_COUNT}" "1" "Release versions"

    rm -rf "${RELEASES_FILE}"
}

verify_release_asset_count_rke2 () {
    # $1 Version under test(VUT)
    VUT="$1"

    echo "\n==== VERIFY ASSET COUNT FOR RKE2 VERSION: ${VUT} ===="
    debug_log "curl -sS -H \"Accept: application/vnd.github+json\" \"https://api.github.com/repos/rancher/rke2/releases/tags/${VUT}\" | jq '.assets | length'"
    
    ASSET_COUNT=$(curl -sS -H "Accept: application/vnd.github+json" "https://api.github.com/repos/rancher/rke2/releases/tags/${VUT}" | jq '.assets | length')
    verify_count "${ASSET_COUNT}" "74" "RKE2 release Asset count"
}

verify_release_asset_count_k3s () {
    # $1 Version under test(VUT)
    VUT="$1"

    echo "\n==== VERIFY ASSET COUNT FOR K3S VERSION: ${VUT} ===="
    debug_log "curl -sS -H \"Accept: application/vnd.github+json\" \"https://api.github.com/repos/k3s-io/k3s/releases/tags/${VUT}\" | jq '.assets | length'"
    
    ASSET_COUNT=$(curl -sS -H "Accept: application/vnd.github+json" "https://api.github.com/repos/k3s-io/k3s/releases/tags/${VUT}" | jq '.assets | length')
    verify_count "${ASSET_COUNT}" "19" "K3S release Asset count"
}

verify_rke2_packaging () {
    # $1 product $2 version_prefix (Ex: v1.31.2-rc4) $3 version_suffix (Ex: rke2r1 or k3s1)
    PRDT="$1"
    V_PREFIX="$2"
    V_SUFFIX="$3"

    RKE2_PKG_FILE="rke2_pkg_${RANDOM}"
    
    echo "\n==== SELINUX RKE2 PACKAGING CHECK: ${PRDT} ${V_PREFIX} ${V_SUFFIX}: ===="

    for p in {1..3}; do
        if echo "${V_PREFIX}" | grep -q "rc"; then
            debug_log "curl -s -H \"Accept: application/vnd.github+json\" https://api.github.com/repos/rancher/rke2-packaging/tags\?page\=${p}\&per_page\=100 | jq '.[].name' >> ${RKE2_PKG_FILE}"
            curl -s -H "Accept: application/vnd.github+json" https://api.github.com/repos/rancher/rke2-packaging/tags\?page\="${p}"\&per_page\=100 | jq '.[].name' >> "${RKE2_PKG_FILE}" 2>&1
        else
            debug_log "curl -s -H \"Accept: application/vnd.github+json\" https://api.github.com/repos/rancher/rke2-packaging/tags\?page\=${p}\&per_page\=100 | jq '.[].name' >> ${RKE2_PKG_FILE}"
            curl -s -H "Accept: application/vnd.github+json" https://api.github.com/repos/rancher/rke2-packaging/tags\?page\="${p}"\&per_page\=100 | jq '.[].name' >> "${RKE2_PKG_FILE}" 2>&1
        fi
    done

    if echo "${V_PREFIX}" | grep -q "rc"; then
        CHANNEL_COUNT=$(cat "${RKE2_PKG_FILE}" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | wc -l)
        OUTPUT=$(cat "${RKE2_PKG_FILE}" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" )
    else
        CHANNEL_COUNT=$(cat "${RKE2_PKG_FILE}" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | grep -v "rc" | wc -l)
        OUTPUT=$(cat "${RKE2_PKG_FILE}" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | grep -v "rc")
    fi

    debug_log "\nOutput:\n ${OUTPUT}"
    verify_count  "${CHANNEL_COUNT}" "1" "RKE2 packaging versions"
    
    rm -rf "${RKE2_PKG_FILE}"
}

verify_prime_registry () {
    # $1 product $2 version_prefix (Ex: v1.31.2-rc4) $3 version_suffix (Ex: rke2r1 or k3s1)
    PRDT="$1"
    V_PREFIX="$2"
    V_SUFFIX="$3"
    SYS_AGENT_OUTFILE="sys_agent_${RANDOM}"
    RKE2_RUNTIME_OUTFILE="rke2_runtime_${RANDOM}"
    echo "\n==== VERIFY PRIME REGISTRY FOR ${PRDT} ${V_PREFIX} ${V_SUFFIX}: ===="

    if [ "${PRDT}" = "rke2" ]; then
        RKE2_RUNTIME_URL="docker://registry.rancher.com/rancher/rke2-runtime"
        if echo $2 | grep -q "rc"; then
            debug_log "skopeo list-tags ${RKE2_RUNTIME_URL} | grep ${V_PREFIX} | grep ${V_SUFFIX} | tee -a ${RKE2_RUNTIME_OUTFILE}"
            skopeo list-tags "${RKE2_RUNTIME_URL}" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | tee -a "${RKE2_RUNTIME_OUTFILE}"
        else
            debug_log "skopeo list-tags ${RKE2_RUNTIME_URL} | grep ${V_PREFIX} | grep ${V_SUFFIX} | grep -v rc | tee -a ${RKE2_RUNTIME_OUTFILE}"
            skopeo list-tags "${RKE2_RUNTIME_URL}" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | grep -v rc | tee -a "${RKE2_RUNTIME_OUTFILE}"
        fi
    
        RKE2_RUNTIME_COUNT=$(cat "${RKE2_RUNTIME_OUTFILE}" | wc -l)
        verify_count "${RKE2_RUNTIME_COUNT}" "1" "RKE2 Runtime(in prime registry)"
    fi

    SYS_AGENT_INSTALLER_URL="docker://registry.rancher.com/rancher/system-agent-installer-${PRDT}"
    debug_log "skopeo list-tags ${SYS_AGENT_INSTALLER_URL} | grep ${V_PREFIX} | grep ${V_SUFFIX} | tee -a ${SYS_AGENT_OUTFILE}"
    skopeo list-tags "${SYS_AGENT_INSTALLER_URL}" | grep "${V_PREFIX}" | grep "${V_SUFFIX}" | tee -a "${SYS_AGENT_OUTFILE}"
    
    SYS_AGENT_COUNT=$(cat "${SYS_AGENT_OUTFILE}" | wc -l)
    verify_count "${SYS_AGENT_COUNT}" "1" "System Agent Installer for ${PRDT} (in prime registry)"

    rm -rf "${SYS_AGENT_OUTFILE}"
    rm -rf "${RKE2_RUNTIME_OUTFILE}"
}

# Main script execution starts here
VERSIONS=$(echo "${INPUT}" | tr "," "\n")
for V in $VERSIONS
do
    echo "==========================================================================
        TESTING VERSION: ${V} 
=========================================================================="
    if echo "${V}" | grep -q "rke2"; then
        PRODUCT="rke2"
    else
        PRODUCT="k3s"
    fi

    VERSION_PREFIX=$(echo "${V}" | cut -d+ -f1)
    VERSION_SUFFIX=$(echo "${V}" | cut -d+ -f2) # Values will be rke2r1/rke2r2/k3s1/k3s2
    
    echo "Version under test: ${V} ; Prefix: ${VERSION_PREFIX} Suffix: ${VERSION_SUFFIX}"

    verify_system_agent_installers "${PRODUCT}" "${VERSION_PREFIX}" "${VERSION_SUFFIX}"
    verify_upgrade_images "${PRODUCT}" "${VERSION_PREFIX}" "${VERSION_SUFFIX}"
    verify_releases "${PRODUCT}" "${VERSION_PREFIX}" "${VERSION_SUFFIX}"
    if [ "${PRODUCT}" = "rke2" ]; then
        verify_rke2_packaging "${PRODUCT}" "${VERSION_PREFIX}" "${VERSION_SUFFIX}"
        verify_release_asset_count_rke2 "${V}"
    else
        verify_release_asset_count_k3s "${V}"
    fi
    verify_prime_registry "${PRODUCT}" "${VERSION_PREFIX}" "${VERSION_SUFFIX}"
    
    echo "===================== DONE ==========================\n"
done
