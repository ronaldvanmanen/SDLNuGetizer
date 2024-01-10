using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using Nuke.Common;
using Nuke.Common.CI;
using Nuke.Common.Execution;
using Nuke.Common.IO;
using Nuke.Common.ProjectModel;
using Nuke.Common.Tooling;
using Nuke.Common.Utilities.Collections;
using static Nuke.Common.EnvironmentInfo;
using static Nuke.Common.IO.FileSystemTasks;
using static Nuke.Common.IO.PathConstruction;
using static System.Runtime.InteropServices.RuntimeInformation;

class Build : NukeBuild
{
    public static int Main () => Execute<Build>(x => x.LinuxBuild);

    readonly List<string> LinuxDependencies = new()
    {
        "build-essential",
        "git",
        "make",
        "pkg-config",
        "cmake",
        "ninja-build",
        "gnome-desktop-testing",
        "libasound2-dev",
        "libpulse-dev",
        "libaudio-dev",
        "libjack-dev",
        "libsndio-dev",
        "libx11-dev",
        "libxext-dev",
        "libxrandr-dev",
        "libxcursor-dev",
        "libxfixes-dev",
        "libxi-dev",
        "libxss-dev",
        "libxkbcommon-dev",
        "libdrm-dev",
        "libgbm-dev",
        "libgl1-mesa-dev",
        "libgles2-mesa-dev",
        "libegl1-mesa-dev",
        "libdbus-1-dev",
        "libibus-1.0-dev",
        "libudev-dev",
        "fcitx-libs-dev",
        "libpipewire-0.3-dev",
        "libwayland-dev",
        "libdecor-0-dev",
        "mono-devel"
    };


    [Parameter("Specifies the architecture for the package (e.g. x64)")]
    readonly string Architecture;

    string Runtime => $"linux-{Architecture:nq}";

    AbsolutePath SourceRootDirectory => RootDirectory / "sources";

    AbsolutePath SourceDirectory => SourceRootDirectory / "SDL";

    AbsolutePath ArtifactsRootDirectory => RootDirectory / "artifacts";

    AbsolutePath BuildRootDirectory => ArtifactsRootDirectory / "build";
    
    AbsolutePath BuildDirectory => BuildRootDirectory / "SDL2" / Runtime;

    AbsolutePath InstallRootDirectory => ArtifactsRootDirectory / "install";

    AbsolutePath InstallDirectory => InstallRootDirectory / "SDL2" / Runtime;

    AbsolutePath PackageRoot => ArtifactsRootDirectory / "pkg";

    Tool Sudo => ToolResolver.GetPathTool("sudo");

    Tool CMake => ToolResolver.GetPathTool("cmake");

    Target InstallLinuxDependencies => _ => _
        .OnlyWhenStatic(() => IsOSPlatform(OSPlatform.Linux))
        .Executes(() =>
        {
            Sudo($"apt-get update");
            var dependencies = string.Join(' ', LinuxDependencies);
            Sudo($"apt-get -y install {dependencies:nq}");
        });

    Target SetupLinuxBuild => _ => _
        .DependsOn(InstallLinuxDependencies)
        .Executes(() =>
        {
            // NOTE: Nuke uses System.Diagnostics.Process.Start to start external processes. See the documentation on
            // https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.arguments for details
            // on how to properly escaped arguments containing spaces.
            var arguments = new string[]
            {
                $"-S", $"{SourceDirectory:dn}",
                $"-B", $"{BuildDirectory:dn}",
                $"-G", $"Ninja",
                $"-DSDL_VENDOR_INFO=Ronald\\x20van\\x20Manen",
                $"-DSDL2_DISABLE_SDL2MAIN=ON",
                $"-DSDL_INSTALL_TESTS=ON",
                $"-DSDL_TESTS=ON",
                $"-DSDL_WERROR=ON",
                $"-DSDL_SHARED=ON",
                $"-DSDL_STATIC=ON",
                $"-DCMAKE_BUILD_TYPE=Release"
            };
            var argumentString = string.Join(' ', arguments);
            CMake(argumentString);
        });

    Target LinuxBuild => _ => _
        .DependsOn(SetupLinuxBuild)
        .Executes(() => 
        {
            CMake($"--build {BuildDirectory} --config Release --parallel");
        });
}
