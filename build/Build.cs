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
    public static int Main () => Execute<Build>(x => x.Compile);

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


    [Parameter("Configuration to build - Default is 'Debug' (local) or 'Release' (server)")]
    readonly Configuration Configuration = IsLocalBuild ? Configuration.Debug : Configuration.Release;

    [LocalPath("/usr/bin/sudo")]
    readonly Tool Sudo;

    Target Clean => _ => _
        .Before(Restore)
        .Executes(() =>
        {
        });

    Target InstallLinuxDependencies => _ => _
        .OnlyWhenStatic(() => IsOSPlatform(OSPlatform.Linux))
        .Executes(() =>
        {
            Sudo($"apt-get update");
            
            foreach (var dependency in LinuxDependencies)
            {
                Sudo($"apt-get -y install {dependency}");
            }
        });

    Target Restore => _ => _
        .Executes(() =>
        {
        });

    Target Compile => _ => _
        .DependsOn(Restore)
        .DependsOn(InstallLinuxDependencies)
        .Executes(() =>
        {
        });

}
