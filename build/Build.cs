using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Nuke.Common;
using Nuke.Common.IO;
using Nuke.Common.Tooling;
using Nuke.Common.Tools.GitVersion;
using Nuke.Common.Tools.NuGet;
using static System.Runtime.InteropServices.RuntimeInformation;
using static Nuke.Common.IO.FileSystemTasks;
using static Nuke.Common.Tools.NuGet.NuGetTasks;

class Build : NukeBuild
{
    public static int Main () => Execute<Build>(x => x.Pack);

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

    [GitVersion]
    readonly GitVersion GitVersion;

    string Runtime
    {
        get
        {
            if (IsOSPlatform(OSPlatform.Linux))
            {
                return $"linux-{Architecture:nq}";
            }
            if (IsOSPlatform(OSPlatform.Windows))
            {
                return $"win-{Architecture:nq}";
            }
            throw new NotSupportedException("Only Linux and Windows are supported at the moment.");
        }
    }

    string PlatformFlags
    {
        get
        {
            if (IsOSPlatform(OSPlatform.Windows))
            {
                return Architecture switch
                {
                    "x64" => "-A x64",
                    "x86" => "-A Win32",
                    _ => string.Empty,
                };
            }
            return string.Empty;
        }
    }
 

    AbsolutePath SourceRootDirectory => RootDirectory / "sources";

    AbsolutePath SourceDirectory => SourceRootDirectory / "SDL";

    AbsolutePath ArtifactsRootDirectory => RootDirectory / "artifacts";

    AbsolutePath BuildRootDirectory => ArtifactsRootDirectory / "build";
    
    AbsolutePath BuildDirectory => BuildRootDirectory / "SDL2" / Runtime;

    AbsolutePath InstallRootDirectory => ArtifactsRootDirectory / "install";

    AbsolutePath InstallDirectory => InstallRootDirectory / "SDL2" / Runtime;

    AbsolutePath PackageRootDirectory => ArtifactsRootDirectory / "pkg";

    string RuntimePackageName => $"SDL2.runtime.{Runtime}";

    string RuntimePackageSpec => $"{RuntimePackageName}.nuspec";

    AbsolutePath RuntimePackageTemplateDirectory => RootDirectory / "packages" / $"{RuntimePackageName}";

    AbsolutePath RuntimePackageBuildDirectory => BuildRootDirectory / $"{RuntimePackageName}.nupkg";

    string DevelopmentPackageName => $"SDL2.devel.{Runtime}";

    string DevelopmentPackageSpec => $"{DevelopmentPackageName}.nuspec";

    AbsolutePath DevelopmentPackageTemplateDirectory => RootDirectory / "packages" / $"{DevelopmentPackageName}";

    AbsolutePath DevelopmentPackageBuildDirectory => BuildRootDirectory / $"{DevelopmentPackageName}.nupkg";

    Tool Sudo => ToolResolver.GetPathTool("sudo");

    Tool CMake => ToolResolver.GetPathTool("cmake");

    Target InstallProjectBuildDependencies => _ => _
        .OnlyWhenStatic(() => IsOSPlatform(OSPlatform.Linux))
        .Executes(() =>
        {
            Sudo($"apt-get update");
            var dependencies = string.Join(' ', LinuxDependencies);
            Sudo($"apt-get -y install {dependencies:nq}");
        });

    Target GenerateProjectBuildSystemOnLinux => _ => _
        .OnlyWhenStatic(() => IsOSPlatform(OSPlatform.Linux))
        .DependsOn(InstallProjectBuildDependencies)
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

    Target GenerateProjectBuildSystemOnWindows => _ => _
        .OnlyWhenStatic(() => IsOSPlatform(OSPlatform.Windows))
        .Executes(() =>
        {
            // NOTE: Nuke uses System.Diagnostics.Process.Start to start external processes. See the documentation on
            // https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.arguments for details
            // on how to properly escaped arguments containing spaces.
            var arguments = new string[]
            {
                $"-S", $"{SourceDirectory:dn}",
                $"-B", $"{BuildDirectory:dn}",
                $"-DCMAKE_INSTALL_LIBDIR=lib/{Architecture}",
                $"-DCMAKE_INSTALL_BINDIR=lib/{Architecture}",
                $"-DCMAKE_INSTALL_INCLUDEDIR=include",
                $"-DSDL_VENDOR_INFO=Ronald\\x20van\\x20Manen",
                $"-DSDL_INSTALL_TESTS=ON",
                $"-DSDL_TESTS=ON",
                $"-DSDL_WERROR=ON",
                $"-DSDL_SHARED=ON",
                $"-DSDL_STATIC=ON",
                $"-DCMAKE_BUILD_TYPE=Release",
                $"{PlatformFlags}"
            };
            var argumentString = string.Join(' ', arguments);
            CMake(argumentString);
        });

    Target GenerateProjectBuildSystem => _ => _
        .DependsOn(GenerateProjectBuildSystemOnLinux)
        .DependsOn(GenerateProjectBuildSystemOnWindows)
        .Executes(() => {});

    Target BuildProject => _ => _
        .DependsOn(GenerateProjectBuildSystem)
        .Executes(() =>
        {
            CMake($"--build {BuildDirectory} --config Release --parallel");
        });

    Target InstallProject => _ => _
        .DependsOn(BuildProject)
        .Executes(() =>
        {
            CMake($"--install {BuildDirectory} --prefix {InstallDirectory}");
        });

    Target BuildRuntimePackage => _ => _
        .DependsOn(InstallProject)
        .Executes(() =>
        {
            RuntimePackageBuildDirectory.CreateOrCleanDirectory();

            CopyDirectoryRecursively(RuntimePackageTemplateDirectory, RuntimePackageBuildDirectory, DirectoryExistsPolicy.Merge);
            CopyFileToDirectory(SourceDirectory / "LICENSE.txt", RuntimePackageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README.md", RuntimePackageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README-SDL.txt", RuntimePackageBuildDirectory);

            var libraryTargetDirectory = RuntimePackageBuildDirectory / "runtimes" / $"{Runtime}" / "native";

            libraryTargetDirectory.CreateDirectory();

            var libraryFiles = InstallDirectory.GlobFiles("lib/libSDL2*so*");
            foreach (var libraryFile in libraryFiles)
            {
                CopyFileToDirectory(libraryFile, libraryTargetDirectory);
            }

            var packSettings = new NuGetPackSettings()
                .SetProcessWorkingDirectory(RuntimePackageBuildDirectory)
                .SetTargetPath(RuntimePackageSpec)
                .SetOutputDirectory(PackageRootDirectory)
                .SetVersion(GitVersion.NuGetVersion);

            NuGetPack(packSettings);
        });

    Target BuildDevelopmentPackage => _ => _
        .DependsOn(InstallProject)
        .Executes(() =>
        {
            DevelopmentPackageBuildDirectory.CreateOrCleanDirectory();

            CopyDirectoryRecursively(DevelopmentPackageTemplateDirectory, DevelopmentPackageBuildDirectory, DirectoryExistsPolicy.Merge);
            CopyDirectoryRecursively(InstallDirectory, DevelopmentPackageBuildDirectory, DirectoryExistsPolicy.Merge);

            var packSettings = new NuGetPackSettings()
                .SetProcessWorkingDirectory(DevelopmentPackageBuildDirectory)
                .SetTargetPath(DevelopmentPackageSpec)
                .SetOutputDirectory(PackageRootDirectory)
                .SetVersion(GitVersion.NuGetVersion)
                .SetNoPackageAnalysis(true);

            NuGetPack(packSettings);
        });

    Target Pack => _ => _
        .DependsOn(BuildRuntimePackage)
        .DependsOn(BuildDevelopmentPackage)
        .Executes(() => {});
}
