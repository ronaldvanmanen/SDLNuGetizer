using NuGet.RuntimeModel;
using Nuke.Common.IO;

static class AbsolutePathExtensions
{
    public static void WriteRuntimeGraph(this AbsolutePath path, RuntimeGraph runtimeGraph)
    {
        JsonRuntimeFormat.WriteRuntimeGraph(path.ToString(), runtimeGraph);
    }
}