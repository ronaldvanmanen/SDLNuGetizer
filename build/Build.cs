using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Nuke.Common;
using Nuke.Common.Git;
using Nuke.Common.IO;
using Nuke.Common.Tooling;
using Nuke.Common.Tools.GitVersion;
using Nuke.Common.Tools.NuGet;
using static System.Runtime.InteropServices.RuntimeInformation;
using static Nuke.Common.IO.FileSystemTasks;
using static Nuke.Common.Tools.NuGet.NuGetTasks;

class Build : NukeBuild
{
    const string ProjectName = "SDL2";

    public static int Main () => Execute<Build>(x => x.BuildPackages);

    readonly List<string> ProjectBuildDependenciesForLinux = new()
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

    AbsolutePath SourceRootDirectory => RootDirectory / "sources";

    AbsolutePath SourceDirectory => SourceRootDirectory / "SDL";

    AbsolutePath ArtifactsRootDirectory => RootDirectory / "artifacts";

    AbsolutePath BuildRootDirectory => ArtifactsRootDirectory / "build";
    
    AbsolutePath BuildDirectory => BuildRootDirectory / $"{ProjectName}" / Runtime;

    AbsolutePath InstallRootDirectory => ArtifactsRootDirectory / "install";

    AbsolutePath InstallDirectory => InstallRootDirectory / $"{ProjectName}" / Runtime;

    AbsolutePath PackageRootDirectory => ArtifactsRootDirectory / "pkg";

    Tool Sudo => ToolResolver.GetPathTool("sudo");

    Tool CMake => ToolResolver.GetPathTool("cmake");

    Tool CTest => ToolResolver.GetPathTool("ctest");

    Target InstallProjectBuildDependencies => _ => _
        .Unlisted()
        .Executes(() =>
        {
            if (IsOSPlatform(OSPlatform.Linux))
            {
                Sudo($"apt-get update");
                var dependencies = string.Join(' ', ProjectBuildDependenciesForLinux);
                Sudo($"apt-get -y install {dependencies:nq}");
            }
        });

    Target GenerateProjectBuildSystem => _ => _
        .DependsOn(InstallProjectBuildDependencies)
        .Executes(() =>
        {
            // NOTE: Nuke uses System.Diagnostics.Process.Start to start external processes. See the documentation on
            // https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.arguments for details
            // on how to properly escaped arguments containing spaces.
            var arguments = new List<string>();

            if (IsOSPlatform(OSPlatform.Windows))
            {
                arguments.Add($"-DCMAKE_INSTALL_LIBDIR=lib/{Architecture}");
                arguments.Add($"-DCMAKE_INSTALL_BINDIR=lib/{Architecture}");
                arguments.Add($"-DCMAKE_INSTALL_INCLUDEDIR=include");
            }

            if (IsOSPlatform(OSPlatform.Linux))
            {
                arguments.Add($"-DSDL2_DISABLE_SDL2MAIN=OFF");
            }

            arguments.Add($"-DSDL_VENDOR_INFO=Ronald\\x20van\\x20Manen");
            arguments.Add($"-DSDL_INSTALL_TESTS=ON");
            arguments.Add($"-DSDL_TESTS=ON");
            arguments.Add($"-DSDL_WERROR=ON");
            arguments.Add($"-DSDL_SHARED=ON");
            arguments.Add($"-DSDL_STATIC=ON");
            arguments.Add($"-DCMAKE_BUILD_TYPE=Release");

            if (IsOSPlatform(OSPlatform.Linux))
            {
                arguments.Add($"-G Ninja");
            }

            if (IsOSPlatform(OSPlatform.Windows))
            {
                switch (Architecture)
                {
                    case "x64":
                        arguments.Add("-A x64");
                        break;
                    case "x86":
                        arguments.Add("-A Win32");
                        break;
                }
            }

            arguments.Add($"-S {SourceDirectory:dn}");
            arguments.Add($"-B {BuildDirectory:dn}");

            CMake(string.Join(' ', arguments));
        });

    Target BuildProject => _ => _
        .DependsOn(GenerateProjectBuildSystem)
        .Executes(() =>
        {
            CMake($"--build {BuildDirectory} --config Release --parallel");
        });

    Target TestProject => _ => _
        .OnlyWhenStatic(() => IsOSPlatform(OSPlatform.Windows))
        .DependsOn(BuildProject)
        .Executes(() =>
        {
            CTest($"-VV --test-dir {BuildDirectory} -C Release");
        });

    Target InstallProject => _ => _
        .DependsOn(TestProject)
        .Executes(() =>
        {
            CMake($"--install {BuildDirectory} --prefix {InstallDirectory}");
        });

    Target BuildRuntimePackage => _ => _
        .Unlisted()
        .DependsOn(InstallProject)
        .Executes(() =>
        {
            var packageName = $"{ProjectName}.runtime.{Runtime}";
            var packageSpec = $"{packageName}.nuspec";
            var packageTemplateDirectory = RootDirectory / "packages" / $"{packageName}";
            var packageBuildDirectory = BuildRootDirectory / $"{packageName}.nupkg";

            packageBuildDirectory.CreateOrCleanDirectory();

            CopyDirectoryRecursively(packageTemplateDirectory, packageBuildDirectory, DirectoryExistsPolicy.Merge);
            CopyFileToDirectory(SourceDirectory / "LICENSE.txt", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README.md", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README-SDL.txt", packageBuildDirectory);

            var libraryTargetDirectory = packageBuildDirectory / "runtimes" / $"{Runtime}" / "native";

            var libraryFiles = InstallDirectory.GlobFiles("lib/libSDL2*so*", $"lib/{Architecture}/*.dll");
            foreach (var libraryFile in libraryFiles)
            {
                CopyFileToDirectory(libraryFile, libraryTargetDirectory);
            }

            var packSettings = new NuGetPackSettings()
                .SetProcessWorkingDirectory(packageBuildDirectory)
                .SetTargetPath(packageSpec)
                .SetOutputDirectory(PackageRootDirectory)
                .SetVersion(GitVersion.NuGetVersion);

            NuGetPack(packSettings);
        });

    Target BuildDevelopmentPackage => _ => _
        .Unlisted()
        .DependsOn(InstallProject)
        .Executes(() =>
        {
            var packageName = $"{ProjectName}.devel.{Runtime}";
            var packageSpec = $"{packageName}.nuspec";
            var packageTemplateDirectory = RootDirectory / "packages" / $"{packageName}";
            var packageBuildDirectory = BuildRootDirectory / $"{packageName}.nupkg";

            packageBuildDirectory.CreateOrCleanDirectory();

            CopyDirectoryRecursively(packageTemplateDirectory, packageBuildDirectory, DirectoryExistsPolicy.Merge);
            CopyDirectoryRecursively(InstallDirectory, packageBuildDirectory, DirectoryExistsPolicy.Merge);
            CopyFileToDirectory(SourceDirectory / "BUGS.txt", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "LICENSE.txt", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README-SDL.txt", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README.md", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "WhatsNew.txt", packageBuildDirectory);
            CopyDirectoryRecursively(SourceDirectory / "docs", packageBuildDirectory / "docs", DirectoryExistsPolicy.Merge);

            var packSettings = new NuGetPackSettings()
                .SetProcessWorkingDirectory(packageBuildDirectory)
                .SetTargetPath(packageSpec)
                .SetOutputDirectory(PackageRootDirectory)
                .SetVersion(GitVersion.NuGetVersion)
                .SetNoPackageAnalysis(true);

            NuGetPack(packSettings);
        });

    Target BuildMultiplatformPackage => _ => _
        .Unlisted()
        .Executes(() =>
        {
            var packageName = $"{ProjectName}";
            var packageSpec = $"{packageName}.nuspec";
            var packageTemplateDirectory = RootDirectory / "packages" / $"{packageName}";
            var packageBuildDirectory = BuildRootDirectory / $"{packageName}.nupkg";

            packageBuildDirectory.CreateOrCleanDirectory();

            CopyDirectoryRecursively(packageTemplateDirectory, packageBuildDirectory, DirectoryExistsPolicy.Merge);
            CopyFileToDirectory(SourceDirectory / "BUGS.txt", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "LICENSE.txt", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README-SDL.txt", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "README.md", packageBuildDirectory);
            CopyFileToDirectory(SourceDirectory / "WhatsNew.txt", packageBuildDirectory);
            CopyDirectoryRecursively(SourceDirectory / "docs", packageBuildDirectory / "docs", DirectoryExistsPolicy.Merge);
            CopyDirectoryRecursively(SourceDirectory / "include", packageBuildDirectory / "lib" / "native" / "include", DirectoryExistsPolicy.Merge);

            var runtime = packageBuildDirectory / "runtime.json";
            var runtimeContent = runtime.ReadAllText();
            Regex.Replace(runtimeContent, "$version$", GitVersion.NuGetVersion);
            runtime.WriteAllText(runtimeContent);

            var packSettings = new NuGetPackSettings()
                .SetProcessWorkingDirectory(packageBuildDirectory)
                .SetTargetPath(packageSpec)
                .SetOutputDirectory(PackageRootDirectory)
                .SetVersion(GitVersion.NuGetVersion)
                .SetNoPackageAnalysis(true);

            NuGetPack(packSettings);
        });

    Target BuildPackages => _ => _
        .DependsOn(BuildRuntimePackage)
        .DependsOn(BuildDevelopmentPackage)
        .DependsOn(BuildMultiplatformPackage);
}
