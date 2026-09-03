// Launches interactive_report/report.py directly against a given report.config,
// bypassing the rest of the pipeline entirely -- see `--report` in
// WorkflowMain.initialise, same early-exit spot as --help/--version. Not a Nextflow
// process: report.py is a long-running Shiny web server, not a short-lived task, and
// this needs to run in the foreground (inheriting the terminal, so Ctrl+C stops it
// and its output streams live) rather than through Nextflow's task executor.
//
// report.py needs shiny/pysam/libsass, none of which exist on the host (confirmed:
// only pandas/matplotlib are present as system packages) -- runs inside
// romualdomf/forest-report (docker/report/Dockerfile), a plain `docker run`, not a
// Nextflow withLabel container (this bypasses the DSL2 workflow entirely, so
// Nextflow's own container executor is never involved).
class ReportLauncher {

    static void launch(String configPath, String projectDirPath) {
        File config = new File(configPath).absoluteFile
        if (!config.isFile()) {
            System.err.println "--report: config file not found: ${config}"
            System.exit(1)
        }
        File reportPy = new File(new File(projectDirPath), 'interactive_report/report.py')
        if (!reportPy.isFile()) {
            System.err.println "--report: report.py not found at ${reportPy} -- is this a valid forest checkout?"
            System.exit(1)
        }

        Map<String, String> values = parseConfig(config)
        String host = values.getOrDefault('host', '127.0.0.1')
        String port = values.getOrDefault('port', '8000')

        // report.config's own paths (written by ReportConfig.generate, or hand-edited
        // in interactive_report/report.config) are always absolute paths under
        // /home/usuario -- out_dir and interactive_report/ both live there, same as
        // every other data path on this host (fastvep_sa_dir, annotsv_annotations_dir,
        // etc. all follow the same convention). Bind-mounting the whole home directory
        // (rather than trying to enumerate every path report.config might reference)
        // mirrors the original manual `docker run -v /home/usuario:/home/usuario`
        // invocation this pipeline's own steller integration was modelled on.
        String cmd = "docker run --rm -p ${port}:${port} " +
            "-v /home/usuario:/home/usuario " +
            "--user \$(id -u):\$(id -g) " +
            "romualdomf/forest-report:latest " +
            "python3 ${reportPy.absolutePath} ${config.absolutePath}"

        println "Launching interactive_report/report.py -- http://${host}:${port}"
        println "(Ctrl+C stops the report server and exits.)"

        ProcessBuilder pb = new ProcessBuilder(['bash', '-c', cmd])
        pb.redirectErrorStream(false)
        pb.inheritIO()
        Process proc = pb.start()
        int exitCode = proc.waitFor()
        System.exit(exitCode)
    }

    private static Map<String, String> parseConfig(File config) {
        Map<String, String> values = [:]
        config.eachLine { line ->
            String trimmed = line.trim()
            if (trimmed.startsWith('#') || !trimmed.contains('=')) {
                return
            }
            List<String> parts = trimmed.split('=', 2) as List<String>
            values[parts[0].trim()] = parts[1].trim()
        }
        return values
    }
}
