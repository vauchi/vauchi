#!/bin/sh
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

workspace=${1:-.}

find "$workspace" \
    \( -type d \( \
        -name .git -o \
        -name .worktrees -o \
        -name .venv -o \
        -name build -o \
        -name node_modules -o \
        -name target \
    \) \) -prune -o \
    -type f -name .gitlab-ci.yml -print
