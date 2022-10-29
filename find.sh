#!/usr/bin/env bash

for i in {0..7}; do nc -vz kate${i}.local 22; done

