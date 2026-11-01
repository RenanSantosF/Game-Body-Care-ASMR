#!/bin/sh
# Ajusta o modelo de build Android do Godot 4.3 para a API exigida pela Play Store (targetSdk 36).
set -e
CFG=android/build/config.gradle
PROPS=android/build/gradle.properties
sed -i -E "s/compileSdk( *): [0-9]+/compileSdk\1: 36/; s/targetSdk( *): [0-9]+/targetSdk\1: 36/; s/buildTools( *): '[0-9.]+'/buildTools\1: '36.0.0'/" "$CFG"
grep -q suppressUnsupportedCompileSdk "$PROPS" || echo "android.suppressUnsupportedCompileSdk=36" >> "$PROPS"
grep -E "compileSdk|targetSdk|buildTools" "$CFG"
