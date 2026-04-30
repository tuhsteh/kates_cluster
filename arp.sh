#!/usr/bin/env bash

arp -a | grep -v "incomplete"

# ? (10.0.0.55) at 62:ef:1a:9:29:38 on en0 ifscope [ethernet]
# ? (10.0.0.56) at 26:23:fe:8e:a:7f on en0 ifscope [ethernet]
# ? (10.0.0.57) at e:99:68:9c:63:7e on en0 ifscope [ethernet]
# ? (10.0.0.58) at 6e:fc:a8:26:69:b0 on en0 ifscope [ethernet]
# ? (10.0.0.59) at 6a:a3:21:fb:5e:aa on en0 ifscope [ethernet]
# ? (10.0.0.60) at 8e:52:b7:d:67:5d on en0 ifscope [ethernet]
# ? (10.0.0.61) at 2:57:32:c3:0:cf on en0 ifscope [ethernet]
# ? (10.0.0.62) at b2:54:6c:3b:66:bc on en0 ifscope [ethernet]
