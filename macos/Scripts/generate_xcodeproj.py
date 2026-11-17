#!/usr/bin/env python3
"""Generates PhotoPic.xcodeproj/project.pbxproj and xcscheme cleanly."""

import hashlib, os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PROJ_DIR = ROOT / "PhotoPic.xcodeproj"
SCHEME_DIR = PROJ_DIR / "xcshareddata" / "xcschemes"


def uid(key: str) -> str:
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:24].upper()


def collect_sources():
    return sorted(p.relative_to(ROOT).as_posix() for b in (ROOT / "macos/PhotoPic", ROOT / "macos/AppEntry") for p in b.rglob("*.swift"))


def build_pbxproj():
    swift_files = collect_sources()
    resources = ["macos/Resources/AppIcon.icns"]
    support = ["macos/Resources/Info.plist", "macos/Resources/PhotoPic.entitlements"]

    p_id, mg_id, sg_id, rg_id, pg_id = uid("PROJECT"), uid("GROUP_ROOT"), uid("GROUP_SOURCES"), uid("GROUP_RESOURCES"), uid("GROUP_PRODUCTS")
    tgt_id, prod_id = uid("TARGET_APP"), uid("PRODUCT_APP")
    sp_id, rp_id, fp_id = uid("PHASE_SOURCES"), uid("PHASE_RESOURCES"), uid("PHASE_FRAMEWORKS")
    pcl_id, tcl_id = uid("CFGLIST_PROJ"), uid("CFGLIST_TARGET")
    cdp, crp, cdt, crt = uid("CFG_PROJ_DEBUG"), uid("CFG_PROJ_RELEASE"), uid("CFG_TGT_DEBUG"), uid("CFG_TGT_RELEASE")

    frefs, bfiles, sbids, rbids, srids, rrids = [], [], [], [], [], []
    for rel in swift_files:
        fid, bid, name = uid(f"F:{rel}"), uid(f"B:{rel}"), os.path.basename(rel)
        frefs.append(f'\t\t{fid} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{rel}"; sourceTree = "<group>"; }};')
        bfiles.append(f'\t\t{bid} = {{isa = PBXBuildFile; fileRef = {fid}; }};')
        srids.append(f'\t\t\t\t{fid},'); sbids.append(f'\t\t\t\t{bid},')

    for rel in resources:
        fid, bid, name = uid(f"F:{rel}"), uid(f"B:{rel}"), os.path.basename(rel)
        frefs.append(f'\t\t{fid} = {{isa = PBXFileReference; lastKnownFileType = image.icns; name = "{name}"; path = "{rel}"; sourceTree = "<group>"; }};')
        bfiles.append(f'\t\t{bid} = {{isa = PBXBuildFile; fileRef = {fid}; }};')
        rrids.append(f'\t\t\t\t{fid},'); rbids.append(f'\t\t\t\t{bid},')

    for rel in support:
        fid, name = uid(f"F:{rel}"), os.path.basename(rel)
        ft = "text.plist.xml" if rel.endswith(".plist") else "text.plist.entitlements"
        frefs.append(f'\t\t{fid} = {{isa = PBXFileReference; lastKnownFileType = {ft}; name = "{name}"; path = "{rel}"; sourceTree = "<group>"; }};')
        rrids.append(f'\t\t\t\t{fid},')

    frefs.append(f'\t\t{prod_id} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PhotoPic.app; sourceTree = BUILT_PRODUCTS_DIR; }};')

    fws = ["AppKit", "AVFoundation", "CoreImage", "CoreMedia", "IOKit", "ImageCaptureCore", "ImageIO", "Metal", "UniformTypeIdentifiers", "Vision"]
    fbids, frids = [], []
    for fw in fws:
        fid, bid = uid(f"FW:{fw}"), uid(f"FB:{fw}")
        frefs.append(f'\t\t{fid} = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {fw}.framework; path = System/Library/Frameworks/{fw}.framework; sourceTree = SDKROOT; }};')
        bfiles.append(f'\t\t{bid} = {{isa = PBXBuildFile; fileRef = {fid}; }};')
        frids.append(f'\t\t\t\t{fid},'); fbids.append(f'\t\t\t\t{bid},')

    def tgt_cfg(cid, name, extra):
        return "\n".join([
            f"\t\t{cid} = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {",
            "\t\t\t\tCODE_SIGN_ENTITLEMENTS = macos/Resources/PhotoPic.entitlements;",
            "\t\t\t\tCODE_SIGN_STYLE = Automatic;", "\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;",
            "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;", "\t\t\t\tINFOPLIST_FILE = macos/Resources/Info.plist;",
            '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");',
            '\t\t\t\tOTHER_SWIFT_FLAGS = ("-package-name", "PhotoPic");',
            '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.kairosvisuals.photopic";',
            '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";', *extra,
            "\t\t\t};", f"\t\t\tname = {name};", "\t\t};",
        ])

    def proj_cfg(cid, name):
        return "\n".join([
            f"\t\t{cid} = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {",
            "\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;", "\t\t\t\tCLANG_ENABLE_MODULES = YES;",
            "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;", "\t\t\t\tSDKROOT = macosx;", "\t\t\t\tSWIFT_VERSION = 6.0;",
            "\t\t\t};", f"\t\t\tname = {name};", "\t\t};",
        ])

    lines = [
        "// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {};", "\tobjectVersion = 56;", "\tobjects = {",
        "/* Begin PBXBuildFile section */", *bfiles, "/* End PBXBuildFile section */",
        "/* Begin PBXFileReference section */", *frefs, "/* End PBXFileReference section */",
        "/* Begin PBXFrameworksBuildPhase section */",
        f"\t\t{fp_id} = {{ isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (", *fbids, "\t\t); runOnlyForDeploymentPostprocessing = 0; };",
        "/* End PBXFrameworksBuildPhase section */",
        "/* Begin PBXGroup section */",
        f'\t\t{mg_id} = {{ isa = PBXGroup; children = ({sg_id}, {rg_id}, {pg_id},', *frids, '\t\t); sourceTree = "<group>"; };',
        f'\t\t{sg_id} = {{ isa = PBXGroup; children = (', *srids, '\t\t); name = Sources; sourceTree = "<group>"; };',
        f'\t\t{rg_id} = {{ isa = PBXGroup; children = (', *rrids, '\t\t); name = Resources; sourceTree = "<group>"; };',
        f'\t\t{pg_id} = {{ isa = PBXGroup; children = ({prod_id},); name = Products; sourceTree = "<group>"; }};',
        "/* End PBXGroup section */",
        "/* Begin PBXNativeTarget section */",
        f'\t\t{tgt_id} = {{ isa = PBXNativeTarget; buildConfigurationList = {tcl_id}; buildPhases = ({sp_id}, {fp_id}, {rp_id}); buildRules = (); dependencies = (); name = PhotoPic; productName = PhotoPic; productReference = {prod_id}; productType = "com.apple.product-type.application"; }};',
        "/* End PBXNativeTarget section */",
        "/* Begin PBXProject section */",
        f'\t\t{p_id} = {{ isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; }}; buildConfigurationList = {pcl_id}; compatibilityVersion = "Xcode 14.0"; developmentRegion = es; hasScannedForEncodings = 0; knownRegions = (es, en, Base); mainGroup = {mg_id}; productRefGroup = {pg_id}; projectDirPath = ""; projectRoot = ""; targets = ({tgt_id},); }};',
        "/* End PBXProject section */",
        "/* Begin PBXResourcesBuildPhase section */",
        f"\t\t{rp_id} = {{ isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (", *rbids, "\t\t); runOnlyForDeploymentPostprocessing = 0; };",
        "/* End PBXResourcesBuildPhase section */",
        "/* Begin PBXSourcesBuildPhase section */",
        f"\t\t{sp_id} = {{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (", *sbids, "\t\t); runOnlyForDeploymentPostprocessing = 0; };",
        "/* End PBXSourcesBuildPhase section */",
        "/* Begin XCBuildConfiguration section */",
        proj_cfg(cdp, "Debug"), proj_cfg(crp, "Release"),
        tgt_cfg(cdt, "Debug", ['\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG";', "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = -Onone;"]),
        tgt_cfg(crt, "Release", ["\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = -O;"]),
        "/* End XCBuildConfiguration section */",
        "/* Begin XCConfigurationList section */",
        f"\t\t{pcl_id} = {{ isa = XCConfigurationList; buildConfigurations = ({cdp}, {crp}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};",
        f"\t\t{tcl_id} = {{ isa = XCConfigurationList; buildConfigurations = ({cdt}, {crt}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};",
        "/* End XCConfigurationList section */",
        "\t};", f"\trootObject = {p_id};", "}", ""
    ]
    return "\n".join(lines), tgt_id


def build_scheme(target_id: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" BuildableName = "PhotoPic.app" BlueprintName = "PhotoPic" ReferencedContainer = "container:PhotoPic.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" BuildableName = "PhotoPic.app" BlueprintName = "PhotoPic" ReferencedContainer = "container:PhotoPic.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
"""


def main():
    PROJ_DIR.mkdir(parents=True, exist_ok=True)
    SCHEME_DIR.mkdir(parents=True, exist_ok=True)
    pbx, target_id = build_pbxproj()
    (PROJ_DIR / "project.pbxproj").write_text(pbx, encoding="utf-8")
    (SCHEME_DIR / "PhotoPic.xcscheme").write_text(build_scheme(target_id), encoding="utf-8")
    print(f"Generated {PROJ_DIR}")


if __name__ == "__main__":
    main()
