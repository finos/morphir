#!/usr/bin/env bash

set -eu

echo $SONATYPE_PGP_SECRET | base64 --decode > gpg_key

gpg --import  --no-tty --batch --yes gpg_key

rm gpg_key

# Build all artifacts
./mill -i __.publishApplicationArtifacts

# Publish all artifacts
./mill -i \
    mill.scalalib.PublishModule/publishAll \
    --sonatypeCreds $SONATYPE_USERNAME:$SONATYPE_PASSWORD \
    --sonatypeUri "https://s01.oss.sonatype.org/service/local" \
    --sonatypeSnapshotUri "https://s01.oss.sonatype.org/content/repositories/snapshots" \
    --gpgArgs --passphrase=$SONATYPE_PGP_PASSWORD,--no-tty,--pinentry-mode,loopback,--batch,--yes,-a,-b \
    --publishArtifacts __.publishApplicationArtifacts \
    --readTimeout  3600000 \
    --awaitTimeout 3600000 \
    --release true \
    --signed  true