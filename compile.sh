#!/bin/bash
# SPDX-License-Identifier:           BSD-3-Clause
# https://spdx.org/licenses
# Copyright (c) 2018 Marvell.
#
###############################################################################
## This is the compile script for Marvell Buildroot                          ##
## This script is called by CI automated builds                              ##
## It may also be used interactively by users to compile the same way as CI  ##
###############################################################################
## WARNING: Do NOT MODIFY the CI wrapper code segments.                      ##
## You can only modify the config and compile commands                       ##
###############################################################################


# Used directory variables:
#  $br2_dir      ./buildroot    <- Mainline Buildroot
#  $br2_sdk_dir  ./sdk-base     <- $br2_wrk_dir  or
#                ./sdk-ext-xx   <- $br2_wrk_dir
#  $br2_out_dir  ./**out***
#
# Path variables:
#  $br2_ext_path  :: make -C BR2_EXTERNAL=${br2_ext_path} $config_name
#  $br2_ext_path  :: generate_defconfig  $config_name   $br2_ext_path
#
br2_wrk_dir=$PWD
br2_sdk_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../.. >/dev/null && pwd )"

if [[ ! -d ${br2_sdk_dir}/../buildroot ]]; then
  echo "   No buildroot directory found."
  exit -1
fi
if [[ -f ${br2_sdk_dir}/../buildroot/_Buildroot-2018.11.x ]]; then
  echo "   Cannot use Buildroot-2018.11.x for SDK11."
  exit -1
fi
br2_dir="$( cd ${br2_sdk_dir}/../buildroot >/dev/null && pwd )"

export br2_wrk_dir
export br2_sdk_dir
export br2_dir

# Define IS_CN10K_A0 flag to specifically define CN10K and CNF10K A0 version. There are
# 1)some specific patches will be applied on firmware and kerenl,
# 2)specific toolchain will be used,
# 3)--enable-cn10k-a0-workarounds wil be used for ODP compiling.
# enable it by -a parameter
export IS_CN10K_A0=

# Init "export" before <set -euo pipefail>
# MAINLINE_SET_NUMBER exported into generate_config script
[ ! $MAINLINE_SET_NUMBER ] && declare -x MAINLINE_SET_NUMBER=4

#-----------------------------------
export sdk_cache_zip_used=""
#export -x sdk_cache_zip_used=true
#-----------------------------------

## =v=v=v=v=v=v=v=v=v=v=v CI WRAPPER - Do not Modify! v=v=v=v=v=v=v=v=v=v=v= ##
set -euo pipefail
shopt -s extglob
##==================================== USAGE ================================##
function usage {
	echo """
Usage: compile [-N | --no_configure] [-e | --echo_only] [-b | --boot_image]
               [<-r | --release> <release_id>] [<-p | --package> <pkg_name>] BUILD_NAME
 or:   compile --list
 or:   compile --help
 or:   compile -b cn96xx
 or:   compile -p linux cn96xx

Compiles Marvell Buildroot similar to the given CI build

 -N, --no_configure   Skip configuration steps (mrproper, make defconfig)
 -c, --config_only    Create configuration, do not compile
 -d, --dflt_out_dir   build all variants into same directory named <output>
 -e, --echo_only      Print out the compilation sequence but do not execute it
 -r, --release        Use release settings, take all sources from tarballs.
                      Otherwise build from sources on GIT (development mode).
 -R                   use GIT-branches <-release> instead <-devel>
 -p, --package        Build a single package along with package dependencies
 -s, --sdk_cache      BUILD_NAME without Kernel, MV-packages and flash-image
 -S, --Source_only    Download all Sources (make source), do not compile
 -x, --xtend_name     Extend defconfig file-name with a given text
 -m, --multi_path     Extend defconfig path by    -m DIRa:DIRn
                       so resulting path is  currDir:DIRa:DIRn:sdk-base
 -f, --flavor <string>  Flavor for auto-generated defconfig
 -k, --kconf <kconfig>  Set/Alternate kernel.config file name
 -C, --Clean_all      Clean all Marvell targets/packages. Do not make
 -l, --list           List all supported BUILD_NAME values and exit
 -b, --boot_image     Build only non-trusted flash image with U-boot bootloader
     --bsne                 trusted flash image with U-boot Signed NOT-Encrypted
     --bse                  trusted flash image with U-boot Signed AND Encrypted
     --buefi                UEFI non-trusted flash image
     --buefi_sne             trusted flash image with UEFI Signed NOT-Encrypted
 -B, --no_boot        Skip the boot image build
 -T  <generic-tag>    Replace GIT/TARBALL configuration according to <tag>
 -T   list            List all valid tag-strings supported by f_tag
     --TAGtc     <tag>  Replace GIT/TARBALL config for Tool-Chain component
     --TAGboot   <tag>  Replace GIT/TARBALL config for Boot-image components
     --TAGdpdk   <tag>  Replace GIT/TARBALL config for Dpdk components
     --TAGkernel <tag>  Replace GIT/TARBALL config for Kernel component
     --TAGbldr   <tag>  Replace GIT/TARBALL config for Buildroot component
     --optee          To build FW with optee (Support cn98xx, cn96xx, cnf95)
     --initramfs      To build initramfs kernel image (might require rebuild)
     --access_secure  To build debug build with access_secure patches
     --octeon_host    When octeon is host
     --linux_4k       To build kernel image with 4k pagesize
 -q                   Quick build without object cleaning
     --nostrip        Change default <BR2_STRIP_strip=Y> to NO strip
 -n                   mainline packages set-Number: -n1/-n2/-n3/-n4/-n0 or -nhost, where
                        set1 basic/minimal rootfs configuration with Networking,
                        set2 ext-optimized for Kernel Network Benchmark (BM),
                        set3 containing Netfilter, IPSEC, tools,
                        set4 QA extension - DEFAULT;
			set0 transparent, customer's overriding (no Boot section)
			sethost for host packages enabled
     --DPDK <y|n>     Overwrite Yes or No for DPDK-package
 -a                   Declare this build is for CN10K or CNF10K A0 verison SoC. It will enable
                      flag IS_CN10K_A0. Relevant components will do specific operations for A0 version
                      if this flag is true
 -M		      Enable Mute mode. Only ERROR logs are shown.
 -h, --help           Display this help and exit
"""
	exit 11
	# Return EAGAIN - non-zero but different from reall error
}
##============================ PARSE ARGUMENTS ==============================##
all_opts=$@
opts_short="NcdeRr:p:x:m:f:k:CsSlbqn:T:hBaM"
opts_long="no_configure,config_only,dflt_out_dir,echo_only,release:,package:"
opts_long=${opts_long},"sdk_cache,Source_only,xtend_name:,multi_path:,flavor:,kconfig:,Clean_all,list"
opts_long=${opts_long},"boot_image,bsne,bse,buefi,nostrip,help,no_boot,buefi_sne"
opts_long=${opts_long},"TAGtc:,TAGboot:,TAGdpdk:,TAGboard:,TAGkernel:,TAGbldr:,DPDK:,optee,initramfs,access_secure,octeon_host,linux_4k"

TEMP=`getopt -a -o ${opts_short} --long ${opts_long} -n 'compile' -- "$@"`

if [ $? != 0 ] ; then
	echo "Error: Failed parsing command options" >&2
	exit 1
fi
eval set -- "$TEMP"

no_configure=
config_only=
dflt_out_dir=
echo_only=
boot_only=
release=
release_id=
release_git=
package=
sdk_cache=
source_only=
xtend_name=
multi_path=
export flavor=
list=
atf_vars=
ddr_top=
cpu_freq=
cp_num=
kernel_dtb=
kernel_config_name=
clean_all=
boot_signed=
boot_encrypted=
boot_uefi=
boot_uefi_signed=
export boot_none=
external_fw=
quick_build_no_clean=
nostrip=
optee_used=
initramfs_used=
linux_4k_pagesize=
export tag_generic=
export tag_toolchain=
export tag_boot_img=
export tag_dpdk=
export tag_board=
export tag_kernel=
export tag_buildroot=
export config_script=
export mv_gcc10=
export dpdk_used=n
export SDK11_mrvl=true
export access_used=
export octeon_host_used=
silent_mode=
# Set default for SDK11 components
mv_gcc10=false; tag_buildroot=22;

while true; do
	case "$1" in
		-N | --no_configure ) no_configure=true; shift ;;
		-c | --config_only )  config_only=true; shift ;;
		-d | --dflt_out_dir ) dflt_out_dir=true; shift ;;
		-e | --echo_only )    echo_only=true; shift ;;
		-r | --release )      release=true; shift; release_id=$1; shift ;;
		-R )                  release_git=true; shift ;;
		-p | --package )      shift; package=$1; shift ;;
		-s | --sdk_cache )    sdk_cache=true; dflt_out_dir=true; shift ;;
		-S | --Source_only )  source_only=true; shift ;;
		-x | --xtend_name )   shift; xtend_name=$1; shift ;;
		-m | --multi_path )   shift; multi_path=$1; shift ;;
		-f | --flavor )       shift; flavor=$1; shift ;;
		-k | --kconf )        shift; kernel_config_name=$1; shift ;;
		-l | --list ) 	      list=true; shift ;;
		-C | --Clean_all )    clean_all=true; shift ;;
		-b | --boot_image )   boot_only=true; shift ;;
		     --bsne )         boot_only=true; boot_signed=true; shift ;;
		     --bse )          boot_only=true; boot_signed=true;
		                      boot_encrypted=true; shift ;;
		     --buefi )        boot_only=true; boot_uefi=true; shift ;;
		     --buefi_sne )     boot_only=true; boot_uefi_signed=true; shift ;;
		-B | --no_boot )      boot_none=true; shift ;;
		-q )                  quick_build_no_clean=true; shift ;;
		     --nostrip )      nostrip=true; shift ;;
		-n )                  shift; MAINLINE_SET_NUMBER=$1; shift ;;
		-h | --help )         usage; ;;
		-T )                  shift; tag_generic=$1; shift ;;
		     --TAGtc )        shift; tag_toolchain=$1; shift ;;
		     --TAGboard )     shift; tag_board=$1; shift ;;
		     --TAGboot )      shift; tag_boot_img=$1; shift ;;
		     --TAGdpdk )      shift; tag_dpdk=$1; shift ;;
		     --TAGkernel )    shift; tag_kernel=$1; shift ;;
		     --TAGbldr )      shift; tag_buildroot=$1; shift ;;
		     --DPDK )         shift; dpdk_used=$1; shift ;;
		     --optee )        optee_used=true; shift ;;
		     --initramfs )    initramfs_used=true; shift ;;
		     --access_secure ) access_used=true; shift ;;
		     --octeon_host )  octeon_host_used=true; shift ;;
		     --linux_4k )  linux_4k_pagesize=true; shift ;;
		-a )                  IS_CN10K_A0=true; shift ;;
		-M )		      silent_mode="-s"; shift ;;
		-- ) shift; break ;;
		* ) break ;;
	esac
done

if [[ $list ]] ; then
	echo "Supported build names:"
	grep -v '^#' "${br2_sdk_dir}/scripts/ci/supported_builds.txt"
	echo
	echo
	exit 0
fi

[[ $# -ne 1 ]] && usage
build_name=$1

grep ^$build_name$ ${br2_sdk_dir}/scripts/ci/supported_builds.txt >&/dev/null ||
	( echo "Error: Unsupported build ${build_name}"; exit -1 )
echo "running compile.sh ${build_name}"
echo "        compile.sh ${all_opts}"
echo

echo "flavor=${flavor}"


start_time=`date`
## =^=^=^=^=^=^=^=^=^=^=^=^  End of CI WRAPPER code -=^=^=^=^=^=^=^=^=^=^=^= ##


########################### BUILDROOT CONFIGURATION ############################
[[ "$dpdk_used" != "y" ]] 

export board_name="customer"
export atf_plat="customer"
export soc_family=
no_board_reconfig=

case $build_name in
	a37xx_esp* )
		board_name="mvebu_espressobin-88f3720";
		cfg_prefix="marvell_armada3k_";
		soc_family="armada3k";
		atf_plat="a3700";
		;;
	a37xx_* )
		board_name="mvebu_db-88f3720";
		cfg_prefix="marvell_armada3k_";
		soc_family="armada3k";
		atf_plat="a3700";
		;;
	a3900* )
		board_name="mvebu_db_armada8k";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="a3900";
		;;
	a70x0* )
		board_name="mvebu_db_armada8k";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="a70x0";
		;;
	a7020_amc )
		board_name="mvebu_db_armada8k";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="a70x0_amc";
		;;
	a80x0_mcbin* )
		board_name="mvebu_mcbin-88f8040";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="a80x0_mcbin";
		;;
	a80x0_ucpe* )
		board_name="mvebu_ucpe-88f8040"
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="a80x0";
		;;
	a80x0_ocp* )
		board_name="mvebu_ocp-88f8040"
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="a80x0_ocp";
                ;;
	a80x0* )
		board_name="mvebu_db_armada8k";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="a80x0";
		;;
	cn91*_crb_C )
		board_name="mvebu_crb_ep_cn9130";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="t9130_crb_ep";
		;;
	cn91*_crb* )
		board_name="mvebu_crb_cn9130";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="t9130_crb";
		;;
	cn91*_C )
		board_name="mvebu_db_cn91xx";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="t9130_ep";
		;;
	cn91* )
		board_name="mvebu_db_cn91xx";
		cfg_prefix="marvell_armada_";
		soc_family="armada";
		atf_plat="t9130";
		;;
	cn96* )
		board_name="octeontx2_96xx";
		cfg_prefix="marvell_octeontx2_";
		soc_family="otx2";
		atf_plat="t96";
		external_fw=true;
		;;
	cn93* )
		board_name="octeontx2_93xx";
		cfg_prefix="marvell_octeontx2_";
		soc_family="otx2";
		atf_plat="t96";
		external_fw=true;
		;;
	cnf95* )
		board_name="octeontx2_95xx";
		cfg_prefix="marvell_octeontx2_";
		soc_family="otx2";
		atf_plat="f95";
		external_fw=true;
		;;
	loki* )
		board_name="octeontx2_loki";
		cfg_prefix="marvell_octeontx2_";
		soc_family="otx2";
		atf_plat="loki";
		external_fw=true;
		;;
	cn98* )
		board_name="octeontx2_98xx";
		cfg_prefix="marvell_octeontx2_";
		soc_family="otx2";
		atf_plat="t98";
		external_fw=true;
		;;
	f95mm* )
		board_name="octeontx2_95mm";
		cfg_prefix="marvell_octeontx2_";
		soc_family="otx2";
		atf_plat="f95mm";
		;;
	cn83* )
		board_name="octeontx_83xx";
		cfg_prefix="marvell_octeontx_";
		soc_family="otx";
		atf_plat="t83";
		external_fw=true;
		;;
	cn81* )
		board_name="octeontx_81xx";
		cfg_prefix="marvell_octeontx_";
		soc_family="otx";
		atf_plat="t81";
		;;
	cn10k* )
		external_fw=true;
		cfg_prefix="marvell_cn10k_";
		soc_family="cn10k";
		;;
	cnf10k* )
		external_fw=true;
		cfg_prefix="marvell_cnf10k_";
		soc_family="cn10k";
		;;
	cn20k* )
                external_fw=true;
                cfg_prefix="marvell_cn20k_";
                soc_family="cn20k";
                ;;
	cnf20k* )
                external_fw=true;
                cfg_prefix="marvell_cnf20k_";
                soc_family="cn20k";
                ;;


	custom_cnf10k )    cfg_prefix="mv_cnf10k_"   ; soc_family="cnf10k"   ; mv_gcc_10=true  	;	external_fw=true; 	no_board_reconfig=true;  ;;
	custom_cn10k )    cfg_prefix="mv_cn10k_"   ; soc_family="cn10k"   ; mv_gcc_10=true  	;	external_fw=true; 	no_board_reconfig=true;  ;;
	custom_cn20k )    cfg_prefix="mv_cn20k_"   ; soc_family="cn20k"   ; mv_gcc_10=true  	;	external_fw=true; 	no_board_reconfig=true;  ;;
	custom_otx2 )     cfg_prefix="mv_otx2_"    ; soc_family="otx2"    ; no_board_reconfig=true;  ;;
	custom_otx )      cfg_prefix="mv_otx_"     ; soc_family="otx"     ; no_board_reconfig=true;  ;;
	custom_armada )   cfg_prefix="mv_armada_"  ; soc_family="armada"  ; no_board_reconfig=true;  ;;
	custom_armada3k ) cfg_prefix="mv_armada3k_"; soc_family="armada3k"; no_board_reconfig=true;  ;;

	* )	echo "Error: Could not set board name." \
		" Unsupported build ${build_name}"; exit -1; ;;
esac

case $build_name in
	sdk* )  device_tree="none"; ;;
	a37xx_esp* ) device_tree="armada-3720-espressobin"; ;;
	a37xx_ddr4_v3_A* )
		# This target will build all kernel DTBs for A37xx family
		device_tree="armada-3720-ddr4-db-v3-A";
		kernel_dtb="marvell/armada-3720-db marvell/armada-3720-db-B ";
		kernel_dtb=$kernel_dtb"marvell/armada-3720-db-C ";
		kernel_dtb=$kernel_dtb"marvell/armada-3720-espressobin";
		;;
	a37xx_ddr4_v3_B* )
		device_tree="armada-3720-ddr4-db-v3-B";
		kernel_dtb="marvell/armada-3720-db-B";
		;;
	a37xx_ddr4_v3_C* )
		device_tree="armada-3720-ddr4-db-v3-C";
		kernel_dtb="marvell/armada-3720-db-C";
		;;
	a3900_A )
		# This target will build all kernel DTBs for A3900 family
		device_tree="armada-3900-vd-A";
		kernel_dtb="marvell/armada-3900-db-vd-A ";
		kernel_dtb=$kernel_dtb"marvell/armada-3900-db-vd-B";
		;;
	a3900_B )
		device_tree="armada-3900-vd-B";
		kernel_dtb="marvell/armada-3900-db-vd-B";
		;;
	a70x0 )
		# This target will build all kernel DTBs for A7K family
		device_tree="armada-7040-db";
		kernel_dtb="marvell/armada-7040-db ";
		if [[ $xtend_name == "tsn" ]]; then
			kernel_dtb=$kernel_dtb" marvell/armada-7040-db-mvpp2x";
		fi
		;;
	a70x0_C ) device_tree="armada-7040-db-C"; ;;
	a70x0_D ) device_tree="armada-7040-db-D"; ;;
	a70x0_B ) device_tree="armada-7040-db-B"; ;;
	a70x0_E ) device_tree="armada-7040-db-E"; ;;
	a7020_amc ) device_tree="armada-7020-amc"; ;;
	a70x0_kr )  device_tree="armada-7040-db"; ;;

	a80x0 )
		# This target will build all kernel DTBs for A8K family
		device_tree="armada-8040-db";
		kernel_dtb="marvell/armada-8040-db marvell/armada-8040-db-B ";
		kernel_dtb=$kernel_dtb"marvell/armada-8040-db-C ";
		kernel_dtb=$kernel_dtb"marvell/armada-8040-db-D ";
		kernel_dtb=$kernel_dtb"marvell/armada-8040-db-E ";
		kernel_dtb=$kernel_dtb"marvell/armada-8040-db-G ";
		kernel_dtb=$kernel_dtb"marvell/armada-8040-db-H ";
		kernel_dtb=$kernel_dtb"marvell/armada-8040-mcbin-single-shot ";
		kernel_dtb=$kernel_dtb"marvell/armada-8040-mcbin";
		;;
	a80x0_B ) device_tree="armada-8040-db-B"; ;;
	a80x0_C ) device_tree="armada-8040-db-C"; ;;
	a80x0_D ) device_tree="armada-8040-db-D"; ;;
	a80x0_E ) device_tree="armada-8040-db-E"; ;;
	a80x0_G ) device_tree="armada-8040-db-G"; ;;
	a80x0_H ) device_tree="armada-8040-db-H"; ;;
	a80x0_kr ) device_tree="armada-8040-db"; ;;
	a80x0_pm ) device_tree="armada-8040-db"; ;;
	a80x0_mcbin_single_shot* )
		device_tree="armada-8040-mcbin-single-shot"; ;;
	a80x0_mcbin* ) device_tree="armada-8040-mcbin"; ;;
	a80x0_ucpe* ) device_tree=""; ;;
	a80x0_ocp ) device_tree="armada-8040-ocp"; ;;
	cn9130 ) device_tree="cn9130-db-A";
		kernel_dtb="marvell/cn9130-db marvell/cn9131-db ";
		kernel_dtb=$kernel_dtb"marvell/cn9132-db ";
		kernel_dtb=$kernel_dtb"marvell/cn9130-crb marvell/cn9131-db ";
		;;
	cn9130_B ) device_tree="cn9130-db-B"; ;;
	cn9130_C ) device_tree="cn9130-db-C"; ;;
	cn9130_crb ) device_tree="cn9130-crb-A"; kernel_dtb=$kernel_dtb"marvell/cn9130-crb"; ;;
	cn9130_crb_B ) device_tree="cn9130-crb-B"; ;;
	cn9130_crb_C ) device_tree="cn9130-crb-C"; ;;
	cn9130_crb-r1p3 ) device_tree="cn9130-crb-r1p3-A"; ;;
	cn9130_crb_B-r1p3 ) device_tree="cn9130-crb-r1p3-B"; ;;
	cn9130_crb_C-r1p3 ) device_tree="cn9130-crb-r1p3-C"; ;;
	cn9131 ) device_tree="cn9131-db-A"; kernel_dtb="marvell/cn9131-db ";cp_num="CP_NUM=2"; ;;
	cn9131_B ) device_tree="cn9131-db-B"; cp_num="CP_NUM=2"; ;;
	cn9131_C ) device_tree="cn9131-db-C"; cp_num="CP_NUM=2"; ;;
	cn9132 ) device_tree="cn9132-db-A"; kernel_dtb="marvell/cn9132-db ";cp_num="CP_NUM=3"; ;;
	cn9132_B ) device_tree="cn9132-db-B"; cp_num="CP_NUM=3"; ;;
	cn9132_C ) device_tree="cn9132-db-C"; cp_num="CP_NUM=3"; ;;
	cn81* ) device_tree=""; ;;
	cn83* ) device_tree=""; ;;
	cn96* ) device_tree=""; ;;
	cn93* ) device_tree=""; ;;
	cnf95* ) device_tree=""; ;;
	loki* ) device_tree=""; ;;
	f95o* ) device_tree=""; ;;
	cn98* ) device_tree=""; ;;
	f95mm* ) device_tree=""; ;;
	cn10k* ) device_tree=""; ;;
	cnf10k* ) device_tree=""; ;;
	cn20k* ) device_tree=""; ;;
	cnf20k* ) device_tree=""; ;;

	custom_* )	;;

	* ) echo "Error: Could not configure device_tree." \
		" Unsupported build ${build_name}"; exit -1;	;;
esac

if [[ $cfg_prefix == "marvell_armada3k_" ]]; then
	case $build_name in
		*_1000_800 ) cpu_freq="CLOCKSPRESET=CPU_1000_DDR_800"; ;;
		*_800_800 ) cpu_freq="CLOCKSPRESET=CPU_800_DDR_800"; ;;
		*_1200_750 ) cpu_freq="CLOCKSPRESET=CPU_1200_DDR_750"; ;;
		* )	;;
	esac

	case $build_name in
		a37xx_esp* ) ddr_top="DDR_TOPOLOGY=5"; ;;
		a37xx_ddr4_v3* ) ddr_top="DDR_TOPOLOGY=3"; ;;

		* )	;;
	esac
fi

if [[ $br2_sdk_dir == $br2_wrk_dir ]]; then
    br2_ext_path=${br2_wrk_dir}
else
  # SolutionS-"X". Alternate/Extend Build-Variant with "ss" if "X" not specified
  if [[ ! $xtend_name ]]; then
    xtend_name="ss"
  fi
  if [[ ! $multi_path ]]; then
    br2_ext_path="${br2_wrk_dir}:${br2_sdk_dir}"
  else
    br2_ext_path="${br2_wrk_dir}:${multi_path}:${br2_sdk_dir}"
  fi
fi


#--- $flavor handler -------------------------------------------
# Fragment-path passed to generate_config as <<<export flavor>>>
# Set flavor names for output and defconfig

#-- Solution flavor -------
if [[ ! $flavor ]]; then
  if [[ ${xtend_name} ]]; then
    ext_cfg_prefix=${xtend_name}_${cfg_prefix}
    ext_build_name=${build_name}-${xtend_name}
  else
    ext_cfg_prefix=${cfg_prefix}
    ext_build_name=${build_name}
  fi
fi
if [[ $flavor ]]; then
  if [[ ${xtend_name} ]]; then
    ext_cfg_prefix=${xtend_name}_${flavor}_${cfg_prefix}
    ext_build_name=${build_name}-${xtend_name}-${flavor}
  else
    ext_cfg_prefix=_${flavor}_${cfg_prefix}
    ext_build_name=${build_name}-${flavor}
  fi
fi
#-- Boot flavor -------------
boot_flavor=
if [[ $boot_signed ]]; then
  if [[ $boot_encrypted ]]; then
    boot_flavor=signed-encrypted
    ext_cfg_prefix=_bse_${cfg_prefix}
  else
    boot_flavor=signed
    ext_cfg_prefix=_bsne_${cfg_prefix}
  fi
  [ $flavor ] && [ $boot_flavor != $flavor ] && boot_flavor="error"
  flavor=$boot_flavor
fi
if [[ $boot_uefi ]]; then
  boot_flavor=uefi
  ext_cfg_prefix=_uefi_${cfg_prefix}
  [ $flavor ] && [ $boot_flavor != $flavor ] && boot_flavor="error"
  flavor=$boot_flavor
fi
if [[ $boot_uefi_signed ]]; then
  boot_flavor=uefi-signed
  ext_cfg_prefix=_uefi_signed_${cfg_prefix}
  [ $flavor ] && [ $boot_flavor != $flavor ] && boot_flavor="error"
  flavor=$boot_flavor
fi
if [[ $boot_none ]] && [[ $soc_family == "otx"* ]] ; then
  external_fw=false
  boot_flavor=none
  # ext_cfg_prefix=_none_${cfg_prefix} - don't loose the $xtend_name
  [ $flavor ] && [ $boot_flavor != $flavor ] && boot_flavor="error"
  flavor=$boot_flavor
fi
if [ "$boot_flavor" == "error" ]; then
  echo "Error: multi-flavor currently not supported"; exit -1
fi


if [ $release ]; then
	config_name=${ext_cfg_prefix}"release_defconfig"
	br2_out_dir="${br2_sdk_dir}/../${ext_build_name}-release-output"
else
  if [ $release_git ];then
    config_name=${ext_cfg_prefix}"rel-devel_defconfig"
    br2_out_dir="${br2_sdk_dir}/../${ext_build_name}-rel-devel-output"
  else
    config_name=${ext_cfg_prefix}"devel_defconfig"
    br2_out_dir="${br2_sdk_dir}/../${ext_build_name}-devel-output"
  fi
fi
if [ $dflt_out_dir ]; then
	br2_out_dir="${br2_sdk_dir}/../output"
fi
# Export var and permanent <br2_out_dir> for sdk-ext utilities' using
export br2_out_dir
echo $br2_out_dir > ${br2_dir}/../br2_out_dir


# Create temporary configuration for this build for keeping the GIT stored config file untouch
if [[ ${sdk_cache} ]]; then
  dot_config_name=".cache_"${build_name}"_"${config_name}
else
  if [[ ! $xtend_name ]] && [[ $flavor ]]; then
    config_name=${build_name}${config_name}
  else
    config_name=${build_name}"_"${config_name}
  fi
  dot_config_name="."${config_name}
fi
out_config_name=".build"${dot_config_name}
rm -f ${br2_out_dir}/.build*

if [[ $clean_all ]]; then
  ${br2_sdk_dir}/scripts/ci/clean-marvell.sh ${br2_out_dir}
  exit 0
fi

config_script="${br2_sdk_dir}/scripts/config.sh --file configs/${dot_config_name}"

if [[ ! -e ${br2_wrk_dir}"/configs/"${config_name} || ${sdk_cache} ]]; then
  ${br2_sdk_dir}/configs.mv_frag/generate_defconfig ${br2_wrk_dir}/configs/${dot_config_name} ${br2_ext_path}
  if [ $release_git ]; then
   sed -i 's/-devel/-release/g' ${br2_wrk_dir}/configs/${dot_config_name}
  fi
else
  cp ${br2_wrk_dir}/configs/${config_name} ${br2_wrk_dir}/configs/${dot_config_name}
fi
save_config_name=$(cut --byte=2-  <<< $dot_config_name)

# Cache compilation fails with netsnmp due to openssl 3.0.0. For cache compilations, f_tag file is not called and 
# need to set openssl to 1.1.0h here.
if [[ ${sdk_cache} ]]; then
      ${config_script} --enable BR2_PACKAGE_OPENSSL_OLD_VERSION
fi

# Create Buildroot configuration updates
octeon_dts_dirs="\$\(BR2_EXTERNAL_MARVELL_SDK_PATH\)/board/marvell/dts"
octeon_dts_dirs=$octeon_dts_dirs"\ ${octeon_dts_dirs}/${atf_plat}"

if [ $release ]; then
	config_cmd=$"""
		${config_script} --set-str MARVELL_RELEASE_ID ${release_id}
	"""
        if [ $(uname -m) == "aarch64" ]; then
		config_cmd=$config_cmd$"""
		          ${config_script} --set-str TOOLCHAIN_EXTERNAL_URL \"file://\\$\(TOPDIR\)/../toolchain/marvell-tools-arm64-1018.0.tar.bz2\"
		"""
	fi

else
	if [ -z ${CROSS_COMPILE:-} ]; then
		echo "Error: Devel build requires non-empty CROSS_COMPILE!"
		exit -1
	fi
	GCC_MAJOR=$(echo __GNUC__ | ${CROSS_COMPILE}\gcc -E -x c - | tail -n 1)
	if [[ "${GCC_MAJOR}" -lt "9" ]]; then
		echo "Error: CROSS_COMPILE GCC${GCC_MAJOR} does not conform to requested GCC10 build"
		exit -1
	fi

	gcc_dir="$( dirname ${CROSS_COMPILE} )/../"
	config_cmd="""
		${config_script} --set-str TOOLCHAIN_EXTERNAL_PATH ${gcc_dir}
	"""
	if [[ $atf_plat == "t81" ]]; then
		config_cmd=$config_cmd"""
			${config_script} -e PACKAGE_CAVIUM_IPFWD_OFFLOAD_GIT
		"""
	fi
fi

[[ ${sdk_cache} ]] && no_board_reconfig=true;
[ $MAINLINE_SET_NUMBER == 0 ] && no_board_reconfig=true;

if [[ ! $no_board_reconfig ]]; then   # ~goto "EndOf Kernel/Marvell/Atf/Boot update"
#--- Kernel/Marvell/Atf/Boot update ---

if [[ $boot_uefi ]]; then
CONFIG_SCRIPT_TARGET_UEFI_PLATFORM="${config_script} --set-str TARGET_UEFI_PLATFORM ${atf_plat}"
else
CONFIG_SCRIPT_TARGET_UEFI_PLATFORM=""
fi

if [[ ! $boot_none ]] && [[ ! $external_fw ]]; then
config_cmd=$config_cmd"""
${config_script} --set-str TARGET_ARM_TRUSTED_FIRMWARE_PLATFORM ${atf_plat}
${config_script} --set-str TARGET_UBOOT_BOARD_DEFCONFIG \"${board_name}\"
${CONFIG_SCRIPT_TARGET_UEFI_PLATFORM}
"""
fi

atf_vars="$( ${config_script} --state TARGET_ARM_TRUSTED_FIRMWARE_ADDITIONAL_VARIABLES )"
if [[ $atf_vars == "undef" ]]; then
	atf_vars=""
fi
atf_env="$( ${config_script} --state TARGET_ARM_TRUSTED_FIRMWARE_ADDITIONAL_ENVIRONMENT )"
if [[ $atf_env == "undef" ]]; then
	atf_env=""
fi


if [[ $boot_uefi ]] && [[ $external_fw ]]; then
config_cmd=$config_cmd"""
${CONFIG_SCRIPT_TARGET_UEFI_PLATFORM}
"""
fi


if [[ $initramfs_used ]]; then
 config_cmd=$config_cmd"""
        ${config_script} --enable BR2_TARGET_ROOTFS_INITRAMFS
        """
fi

#Fw debug builds - access-secure
if [[ $access_used ]]; then
 config_cmd=$config_cmd"""
        ${config_script} --enable BR2_MARVELL_DEBUG_ACCESS_SECURE
        """
fi

#Using octeon as host
if [[ $octeon_host_used ]]; then
 config_cmd=$config_cmd"""
        ${config_script} --enable BR2_HOST_IS_OCTEON
        """
fi

#Build 4k pagesize
if [[ $linux_4k_pagesize ]]; then
 config_cmd=$config_cmd"""
        ${config_script} --enable BR2_ARM64_PAGE_SIZE_4K
	${config_script} --disable BR2_ARM64_PAGE_SIZE_64K
        """
fi

#Enable OPTEE
if [ $optee_used ]; then
	if [[ $atf_plat == "t96" || $atf_plat == "f95" || $atf_plat == "t98" || $soc_family == "cn10k" ]]; then
	config_cmd=$config_cmd"""
        ${config_script} --enable BR2_PACKAGE_OPTEE
        ${config_script} --enable BR2_PACKAGE_OPTEE_CLIENT
	${config_script} --enable BR2_PACKAGE_OPTEE_TEST
	"""
        if [[ ! $release ]]; then
                config_cmd=$config_cmd"""
                ${config_script} --enable BR2_PACKAGE_OPTEE_GIT
                """
        fi
	else
		echo "Optee does not support $atf_plat SoC"
		exit -1
	fi #platform specific
fi #optee_tag used




# Set platform-specific parameters
if [[ $cfg_prefix == *"_armada"* ]]; then
	atf_vars="${atf_vars} ${cp_num}"
	config_cmd=$config_cmd"""
	${config_script} --set-str TARGET_UBOOT_CUSTOM_DTS_NAME ${device_tree}
	${config_script} -e PACKAGE_ODP_PLATFORM_MUSDK
	"""
	# If the kernel DB name is not the same as the u-boot one, use it
	if [[ $kernel_dtb ]]; then
		config_cmd=$config_cmd"""
		${config_script} --set-str LINUX_KERNEL_INTREE_DTS_NAME \"${kernel_dtb}\"
		"""
	else
		config_cmd=$config_cmd"""
		${config_script} --set-str LINUX_KERNEL_INTREE_DTS_NAME marvell/${device_tree}
		"""
	fi

	if [[ $cfg_prefix == "marvell_armada_" ]]; then
		# Armada 7K/8K
		config_cmd=$config_cmd"""
		${config_script} -e TARGET_BINARIES_MARVELL
		"""
	else
		# Armada 37xx
		atf_vars="${atf_vars} ${cpu_freq} ${ddr_top}"
	fi

	# Allow U-Boot configuration file update
	uboot_config_fixup_script_path="\$(BR2_EXTERNAL_MARVELL_SDK_PATH)/scripts/config_uboot_fixup.sh"
	config_cmd=$config_cmd"""
	${config_script} -e TARGET_UBOOT_CUSTOM_CONFIG_FIXUP
	${config_script} --set-str TARGET_UBOOT_CONFIG_FIXUP_SCRIPT_PATH \"\\${uboot_config_fixup_script_path}\"
	"""

else
	# OcteonTX/TX2
	if [[ $atf_plat == "t81" ]]; then
		config_cmd=$config_cmd"""
		${config_script} -e PACKAGE_CONFIG_CAVIUM_IPFWD_OFFLOAD
		"""
	else
		config_cmd=$config_cmd"""
		${config_script} -d PACKAGE_CONFIG_CAVIUM_IPFWD_OFFLOAD
		"""
	fi
	if [[ ! $boot_none ]] && [[ ! $external_fw ]]; then
		config_cmd=$config_cmd"""
		${config_script} --set-str TARGET_MARVELL_BDK_PLATFORM \"${atf_plat}\"
		${config_script} --set-str TARGET_MARVELL_BDK_ADDITIONAL_DTS \"${octeon_dts_dirs}\"
		${CONFIG_SCRIPT_TARGET_UEFI_PLATFORM}
		"""
	fi
	if [[ $atf_plat == "t96" || $atf_plat == "f95" || $atf_plat == "loki" || $atf_plat == "t98" || $atf_plat = "f95mm" || $atf_plat = "f95o" ]]; then
		atf_env=${atf_env}
	fi
fi
# prefix all variable names (beginning with $) with escape symbols
# for preventing from variable evaluation by the --set-str commands
if [[ ! $boot_none ]] && [[ ! $external_fw ]]; then
config_cmd=$config_cmd"""
${config_script} --set-str TARGET_ARM_TRUSTED_FIRMWARE_ADDITIONAL_ENVIRONMENT \"${atf_env/\$/\\\$}\"
${config_script} --set-str TARGET_ARM_TRUSTED_FIRMWARE_ADDITIONAL_VARIABLES \"${atf_vars/\$/\\\$}\"
"""
fi

# Support for diferent platforms
if [[ $build_name =~ cn10k* || $build_name =~ cnf10k* || $build_name =~ cn20k* || $build_name =~ cnf20k* ]];
then
      config_cmd=$config_cmd"""
                ${config_script} --set-str BR2_TARGET_MARVELL_EXTERNAL_FW_PLATFORM  \"${build_name}\"
      """
else
	config_cmd=$config_cmd"""
                ${config_script} --set-str BR2_TARGET_MARVELL_EXTERNAL_FW_PLATFORM  \"${atf_plat}\"
      """	
fi

# Kernel 4.18
if [[ $build_name =~ _lk4_18 ]]; then
	if [ $release ]; then
		config_cmd=$config_cmd"""
		${config_script} --set-str LINUX_KERNEL_CUSTOM_TARBALL_LOCATION \"file\://\\\$(TOPDIR)/../base-sources-\\\$(BR2_MARVELL_RELEASE_ID)/linux/sources-linux-4.18.20-\\\$(BR2_MARVELL_RELEASE_ID).tar.bz2\"
		"""
	else
		config_cmd=$config_cmd"""
		${config_script} --set-str LINUX_KERNEL_CUSTOM_REPO_VERSION \"linux-4.18.20-devel\"
		"""
	fi
fi


if [ $kernel_config_name ]; then
 kernel_config="\$(BR2_EXTERNAL_MARVELL_SDK_PATH)/board/marvell"
 kernel_config=$kernel_config/$kernel_config_name
 config_cmd=$config_cmd"""
 ${config_script} --disable BR2_LINUX_KERNEL_DEFCONFIG
 ${config_script} --enable BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG
 ${config_script} --set-str BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE \"\\$kernel_config\"
 """
fi

#--- EndOf Kernel/Marvell/Atf/Boot update ---
fi #${no_board_reconfig}

set +u
if [[ ! ${sdk_cache} ]]; then
	if [[ ! -z $LOCAL_BUILD_PATH ]]; then
		config_cmd=$config_cmd"""
		${config_script} --set-str BR2_PRIMARY_SITE \"\$LOCAL_BUILD_PATH\"
		${config_script} --disable BR2_PRIMARY_SITE_ONLY
		"""
	fi
fi #$LOCAL_BUILD_PATH
set -u

# cn10k-A0 toolchain selection with sdk-cache
if [[ ! -z $IS_CN10K_A0 ]] && [[ $dflt_out_dir ]] && [[ $release ]]; then
        rm -f $br2_out_dir/build/toolchain-external-custom/.stamp*
fi


dropbear=$( ${config_script} --state BR2_PACKAGE_DROPBEAR )
if [[ $dropbear == "n" ]] && [[ $sdk_cache ]]; then
        echo "Removing dropbear. Disabled in some extension"
	find $br2_out_dir/target/ -name '*dropbear*' -delete
fi



# Copy the MAKEFILE file containing Development offload source paths list,
# add to "defconfig" the record pointing to this file.
# Do NOT copy/update the file if it already exists.
if [[ ! $sdk_cache ]]; then
  if [ ! -f ${br2_sdk_dir}/../override_srcdir.mk ]; then
    override_src=${br2_wrk_dir}/configs/override_srcdir.mk
    if [ ! -f ${override_src} ]; then
      override_src=${br2_sdk_dir}/configs/override_srcdir.mk
    fi
    config_cmd=$config_cmd"""
    cp  ${override_src} ${br2_sdk_dir}/../
    """
  fi
  config_cmd=$config_cmd"""
  echo '' >> ${br2_wrk_dir}/configs/${dot_config_name}
  echo 'BR2_PACKAGE_OVERRIDE_FILE=\"\$(TOPDIR)/../override_srcdir.mk\"' >> ${br2_wrk_dir}/configs/${dot_config_name}
  """
fi


# No strip for debug information
if [ $nostrip ]; then
  config_cmd=$config_cmd"""
  ${config_script} --keep-case --set-val BR2_STRIP_strip n
  """
fi


# define commands for building platform-specific flash image
if [[ $boot_only ]]; then
	# The build has dependencies, so only 1 final target may be called.
	# The dirclean has no dependencies and should be done explicitly.
	target_clean=
	if [ $boot_uefi ]; then
		target_clean+="uefi-dirclean "
	else
		if [[ ! $external_fw ]]; then
			target_clean+="optee-os-dirclean uboot-dirclean "
		fi
	fi

	if [[ ! $external_fw ]]; then
		target_clean+="arm-trusted-firmware-dirclean "
	fi

	if [[ $cfg_prefix == *"_armada"* ]]; then
		target_clean+="binaries-marvell-dirclean "
	else
		if [[ ! $external_fw ]]; then
			target_clean+="marvell-bdk-dirclean "
		else
			target_clean+="marvell-external-fw-dirclean "
		fi
	fi
	if [ $quick_build_no_clean ]; then
		target_clean=
		rm -f ${br2_out_dir}/build/uefi-*/.stamp_rsynced
		rm -f ${br2_out_dir}/build/uefi-*/.stamp_built
		rm -f ${br2_out_dir}/build/uboot-*/.stamp_rsynced
		rm -f ${br2_out_dir}/build/uboot-*/.stamp_built
		rm -f ${br2_out_dir}/build/marvell-bdk-*/.stamp_images_installed
		if [ $boot_uefi ]; then
			target+="uefi "
		else
			target+="optee-os uboot "
		fi
	else
		target=$target_clean
	fi
	if [[ $cfg_prefix == *"_armada"* ]]; then
		target+="arm-trusted-firmware "
	else
		target+="marvell-external-fw "
	fi
fi

if [[ -n "$package" ]]; then
	if [ $quick_build_no_clean ]; then
		rm -f ${br2_out_dir}/build/${package}-*/.stamp_rsynced
		rm -f ${br2_out_dir}/build/${package}-*/.stamp_built
		target+="${package} "
	else
		target+="${package}-dirclean ${package} "
	fi
fi

if [[ -z $boot_only ]] && [[ -z $package ]]; then
	target="all"
fi


build_flags="" # not used in u-boot-2018
logfile="${br2_out_dir}/$$.make.log"
###############################################################################


## =v=v=v=v=v=v=v=v=v=v=v CI WRAPPER - Do not Modify! v=v=v=v=v=v=v=v=v=v=v= ##
cmd="""
set -x
pwd"""
## =^=^=^=^=^=^=^=^=^=^=^=^  End of CI WRAPPER code -=^=^=^=^=^=^=^=^=^=^=^= ##


# Use function for correct conditions in/out of the WRAPPER cmd=$cmd"""..."""
function check_config {
  if [[ $sdk_cache ]]; then
    if [ $sdk_cache_zip_used ]; then
      f_ext=".tar.gz"
    else
      f_ext=".tar"
    fi
    cache_config_tmp=${br2_out_dir}/sdk_cache_config.tmp
    cat $(dirname $0)/sdk_cache_hash >> ${br2_wrk_dir}/configs/${dot_config_name}
    cp ${br2_wrk_dir}/configs/${dot_config_name} ${cache_config_tmp}
    ${br2_sdk_dir}/scripts/config.sh --file ${cache_config_tmp} --set-str MARVELL_RELEASE_ID "cache"
    cache_config_id=$(crc32 ${cache_config_tmp})
    cache_file_name="sdk_cache-"${soc_family}-${cache_config_id}
    cache_fname1=${br2_out_dir}/../${cache_file_name}${f_ext}
    cache_fname2=${br2_out_dir}/../${cache_file_name}.out${f_ext}
    if [[ -e $cache_fname1 || -e $cache_fname2 ]] ;then
      set +x
      echo
      echo " No SDK-cache update needed for existing <${cache_file_name}*${f_ext}>"
      echo
      if [[ ! $config_only ]]; then
      echo "============================End of build==============================="
      echo
      fi
      exit 0
    fi
    rm ${cache_config_tmp}
    rm -f ${br2_out_dir}/images/*cache*_defconfig
  fi
}

##################################### CONFIG ##################################
[[ $no_configure ]] || cmd=$cmd"""
${config_cmd}
mkdir -p ${br2_out_dir}
make -C ${br2_dir} O=${br2_out_dir} BR2_EXTERNAL=${br2_ext_path} ${dot_config_name}
touch -f ${br2_out_dir}/${out_config_name}
mkdir -p ${br2_out_dir}/images
check_config
cp ${br2_wrk_dir}/configs/${dot_config_name} ${br2_out_dir}/images/${save_config_name}
"""

#### Keep work-directory and compile.sh command with given options
cmd=$cmd"""
pwd > $br2_out_dir/images/compile.sh-command
ps -x -o command 2>/dev/null | grep --max-count=1 compile.sh >> $br2_out_dir/images/compile.sh-command
"""

if [[ $config_only ]]; then
	echo "$cmd"
	eval "$cmd"
	exit 0
fi

#################### DOWNLOAD ALL SOURCES #####################################
if [ $source_only ]; then
cmd=$cmd"""
make -C ${br2_out_dir} source
"""
  echo "$cmd"
  eval "$cmd"
  set +x
  echo "=========================  OK  ==========================================="
  echo "All sources are downloaded into buildroot/dl/ and stamped in output/build/"
  echo .
  exit 0
fi

#################################### COMPILE ##################################

cmd=$cmd"""
make ${silent_mode} -C ${br2_out_dir} ${target}
set +x
echo \"============================End of build===============================\"
"""
###############################################################################


## =v=v=v=v=v=v=v=v=v=v=v CI WRAPPER - Do not Modify! v=v=v=v=v=v=v=v=v=v=v= ##
if [[ $echo_only ]]; then
	echo "$cmd"
	exit 0
fi

eval "$cmd"
## =^=^=^=^=^=^=^=^=^=^=^=^  End of CI WRAPPER code -=^=^=^=^=^=^=^=^=^=^=^= ##


# Post-build (copy, zip, rename ...)
# ----------------------------------
k_dir=$(find ${br2_out_dir}/build/  -maxdepth 1 -name "linux-linux*")
if [[ -d "${k_dir}" && -f "${k_dir}/.config" ]]; then
	cp ${k_dir}/.config ${br2_out_dir}/images/Kernel.config
else
  k_dir=$(find ${br2_out_dir}/build/  -maxdepth 1 -name "linux-custom")
  if [[ -d "${k_dir}" && -f "${k_dir}/.config" ]]; then
	cp ${k_dir}/.config ${br2_out_dir}/images/Kernel.config
  fi
fi

# Time of build should be out of wrapper
echo "     started at $start_time" > ${br2_out_dir}/${out_config_name}
echo "       ended at `date`"     >> ${br2_out_dir}/${out_config_name}
cat ${br2_out_dir}/${out_config_name}

if [ $sdk_cache ]; then
  ${br2_sdk_dir}/scripts/ci/sdk_cache_pack.sh $soc_family ${br2_wrk_dir}/configs/${dot_config_name}
  echo " End cache-pack `date`"     >> ${br2_out_dir}/${out_config_name}
  cat ${br2_out_dir}/${out_config_name}
fi

