@echo off
chcp 65001 > nul
:: 65001 - UTF-8

cd /d "%~dp0.."
call service.bat status_zapret
call service.bat check_updates
call service.bat load_game_filter
echo:

set "BIN=%~dp0..\bin\"
set "LISTS=%~dp0..\lists\"
cd /d %BIN%

start "zapret: %~n0" /min "%BIN%winws.exe" --wf-tcp=80,443,444-65535 --wf-udp=443,444-65535 ^
--filter-udp=443 --hostlist="%LISTS%russia-youtubeQ.txt" --dpi-desync=fake,udplen --dpi-desync-udplen-increment=8 --dpi-desync-udplen-pattern=0x0E0F0E0F --dpi-desync-fake-quic="%BIN%quic_7.bin" --dpi-desync-cutoff=n3 --dpi-desync-repeats=2 --new ^
--filter-tcp=443 --hostlist-domains=googlevideo.com --hostlist="%LISTS%russia-youtube.txt" --dpi-desync=multisplit --dpi-desync-split-seqovl=1 --dpi-desync-split-pos=sld+1 --new ^
--filter-tcp=443 --hostlist-domains=ntc.party --hostlist="%LISTS%russia-discord.txt" --dpi-desync=multisplit --dpi-desync-split-seqovl=286 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_11.bin" --dup=2 --dup-cutoff=n3 --new ^
--filter-tcp=80 --hostlist-domains=cloudfront.net,amazon.com,amazonaws.com,awsstatic.com,epicgames.com --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=2 --dpi-desync-split-pos=sld+1 --dpi-desync-fake-http="%BIN%http_fake_MS.bin" --dpi-desync-fooling=md5sig --dup=2 --dup-fooling=md5sig --dup-cutoff=n3 --new ^
--filter-tcp=80 --ipset="%LISTS%cloudflare-ipset.txt" --ipset-exclude-ip=1.1.1.1,1.0.0.1,212.109.195.93,83.220.169.155,141.105.71.21,18.244.96.0/19,18.244.128.0/19 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=2 --dpi-desync-split-pos=sld+1 --dpi-desync-fake-http="%BIN%http_fake_MS.bin" --dpi-desync-fooling=md5sig --dup=2 --dup-fooling=md5sig --dup-cutoff=n3 --new ^
--filter-tcp=443,444-65535 --hostlist-domains=awsglobalaccelerator.com,cloudfront.net,amazon.com,amazonaws.com,awsstatic.com,epicgames.com --dpi-desync=multisplit --dpi-desync-split-seqovl=211 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_5.bin" --new ^
--filter-tcp=443,444-65535 --ipset="%LISTS%cloudflare-ipset.txt" --ipset-exclude-ip=1.1.1.1,1.0.0.1,212.109.195.93,83.220.169.155,141.105.71.21,18.244.96.0/19,18.244.128.0/19 --dpi-desync=multisplit --dpi-desync-split-seqovl=211 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_5.bin" --new ^
--filter-udp=443,444-65535 --hostlist-domains=awsglobalaccelerator.com,cloudfront.net,amazon.com,amazonaws.com,awsstatic.com,epicgames.com --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-fake-unknown-udp="%BIN%quic_6.bin" --dpi-desync-repeats=2 --dpi-desync-cutoff=n4 --dpi-desync-ttl=7 --new ^
--filter-udp=443,444-65535 --ipset="%LISTS%cloudflare-ipset.txt" --ipset-exclude-ip=1.1.1.1,1.0.0.1,212.109.195.93,83.220.169.155,141.105.71.21,18.244.96.0/19,18.244.128.0/19 --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-fake-unknown-udp="%BIN%quic_6.bin" --dpi-desync-repeats=2 --dpi-desync-cutoff=n4 --dpi-desync-ttl=7 --new ^
--filter-l3=ipv6 --filter-udp=50000-50090 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-autottl6 --dup=2 --dup-autottl6 --dup-cutoff=n3 --new ^
--filter-l3=ipv4 --filter-udp=50000-50090 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-autottl --dup=2 --dup-autottl --dup-cutoff=n3