# Runtime for interactive_report/report.py (Shiny for Python app used by --report,
# see main.nf's WorkflowMain.initialise/lib/ReportLauncher.groovy). Neither `shiny` nor
# `pysam` exist on the host (confirmed: only pandas/matplotlib are present as system
# packages) -- report.py needs both, so it gets its own image, same reasoning as every
# other tool in this pipeline that isn't already covered by an existing container.
#
# Published at romualdomf/forest-report (hardcoded in the --report launch command --
# not a Nextflow withLabel container, since --report bypasses the whole DSL2 workflow
# and runs report.py via a plain `docker run`, not through Nextflow's own executor).
#   docker build -t romualdomf/forest-report:latest docker/report
#   docker push romualdomf/forest-report:latest

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Debian bookworm's pip refuses plain "pip install" (PEP 668,
# externally-managed-environment) without this -- same workaround already used in
# docker/cnv_ensemble/Dockerfile.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# pysam has prebuilt manylinux wheels for this platform/Python version -- no htslib
# build toolchain needed here (unlike building AnnotSV/tldr from source elsewhere in
# this repo).
#
# libsass: report.py builds a custom ui.Theme(preset="shiny").add_defaults(...) --
# without libsass, shiny raises ImportError("The 'libsass' package is required to
# compile custom themes") the first time it tries to render, at app startup, not at
# import time -- only caught by actually running report.py against a real config, not
# by "python3 -c 'import shiny'" alone.
RUN pip install --no-cache-dir shiny pysam pandas matplotlib libsass

# matplotlib tries to create its config dir at $HOME/.config/matplotlib on first
# import; $HOME does not exist for the arbitrary non-root UID this pipeline always
# runs containers as (--user $(id -u):$(id -g), no matching /etc/passwd entry --
# same reasoning as base.config's runOptions elsewhere in this repo), so that mkdir
# fails with a permission error every single run (harmless -- matplotlib silently
# falls back to a tmp dir -- but noisy). Point it at a directory that is always
# writable regardless of UID instead.
ENV MPLCONFIGDIR=/tmp/matplotlib

WORKDIR /data
