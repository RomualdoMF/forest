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
        String displayHost = values.getOrDefault('host', '127.0.0.1')
        String port = values.getOrDefault('port', '8000')

        // report.py binds Uvicorn to whatever `host` says in the config it's given --
        // fine when running report.py directly on a host without Docker (report.config's
        // own default, 127.0.0.1, is meant for that case), but fatal here: Docker's
        // `-p port:port` publishing forwards to the CONTAINER's own external network
        // interface, never to its internal loopback. A process bound to 127.0.0.1
        // inside the container is invisible to `-p`, no matter what -- the published
        // port still accepts the TCP connection (docker-proxy answers), but nothing
        // ever responds on it, which looks like a hang/reset, not "connection refused"
        // (confirmed for real: curl against a real report.config with the default
        // host=127.0.0.1 connected but never got a response; forcing the in-container
        // bind to 0.0.0.0 and retrying immediately fixed it). So the config actually
        // fed to report.py inside the container always forces host=0.0.0.0, regardless
        // of what the user's own report.config says -- via a throwaway copy, so the
        // user's file on disk is never rewritten. The user-facing URL printed below
        // still uses the ORIGINAL host value (0.0.0.0 isn't something you type into a
        // browser).
        File dockerConfig = File.createTempFile('report-docker-', '.config', config.parentFile)
        dockerConfig.deleteOnExit()
        dockerConfig.withWriter { w ->
            config.eachLine { line ->
                if (line.trim().replaceAll(/\s+/, '').startsWith('host=')) {
                    w.writeLine('host = 0.0.0.0')
                } else {
                    w.writeLine(line)
                }
            }
        }

        // report.config's own paths (written by ReportConfig.generate, or hand-edited
        // in interactive_report/report.config) are always absolute paths under the
        // invoking user's home directory -- out_dir and interactive_report/ both live
        // there, same convention as every other data path in this pipeline
        // (fastvep_sa_dir, annotsv_annotations_dir, etc.). Bind-mounting the whole
        // home directory (rather than trying to enumerate every path report.config
        // might reference) mirrors the original manual
        // `docker run -v $HOME:$HOME` invocation this pipeline's own steller
        // integration was modelled on.
        //
        // The home directory MUST be read at runtime (System.getenv('HOME')), not
        // hardcoded -- a first version of this hardcoded /home/usuario (the host this
        // was developed/tested on) and broke immediately on a second host where the
        // invoking user's home is /home/romualdo: the container only had
        // /home/usuario mounted, so report.py -- genuinely present on the host --
        // was invisible inside the container ("No such file or directory") even
        // though the path Nextflow printed was correct. Also defensively mounts the
        // config file's and the forest checkout's own directories in case either
        // ends up outside $HOME on some host (not seen in practice, but the whole
        // point of this fix is not hardcoding an assumption like that again) --
        // deduplicated against $HOME (and each other) the same way fastVEP's
        // bind-mounts are deduplicated in base.config, so two -v flags for the same
        // host path (a hard "Duplicate mount point" error from Docker) can't happen.
        String home = System.getenv('HOME') ?: System.getProperty('user.home')
        List<String> mountDirs = [home]
        [config.parentFile, reportPy.parentFile].each { dir ->
            String path = dir.absolutePath
            boolean covered = mountDirs.any { path == it || path.startsWith(it + File.separator) }
            if (!covered) {
                mountDirs << path
            }
        }
        String mountFlags = mountDirs.collect { "-v ${it}:${it}" }.join(' ')

        String cmd = "docker run --rm -p ${port}:${port} " +
            "${mountFlags} " +
            "--user \$(id -u):\$(id -g) " +
            "romualdomf/forest-report:latest " +
            "python3 ${reportPy.absolutePath} ${dockerConfig.absolutePath}"

        println "Launching interactive_report/report.py -- http://${displayHost}:${port}"
        println "(Ctrl+C stops the report server and exits.)"

        ProcessBuilder pb = new ProcessBuilder(['bash', '-c', cmd])
        pb.redirectErrorStream(false)
        pb.inheritIO()
        Process proc = pb.start()
        int exitCode = proc.waitFor()
        dockerConfig.delete()
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
