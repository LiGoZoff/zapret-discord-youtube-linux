@echo off
chcp 65001 > nul
:: 65001 - UTF-8

cd /d "%~dp0"
call service.bat status_zapret
call service.bat check_updates
call service.bat load_game_filter
echo:

set "BIN=%~dp0..\bin\"
set "LISTS=%~dp0..\lists\"
cd /d %BIN%

start "zapret: %~n0" /min "%BIN%winws.exe" --wf-tcp=443,2053,2083,2087,2096,8443 --wf-udp=443,19294-19344,50000-50100 ^
--filter-tcp=443 --hostlist="%LISTS%list-google.txt" --dpi-desync=multisplit --dpi-desync-split-pos=1,sniext+1 --dpi-desync-split-seqovl=1 --new
--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-fake-discord="%BIN%quic_initial_www_google_com.bin" --dpi-desync-fake-stun="%BIN%quic_initial_www_google_com.bin" --dpi-desync-repeats=6 --new ^
--filter-tcp=443 --hostlist="%LISTS%russia-discord.txt" --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=rzd.ru --dpi-desync-hostfakesplit-midhost=host-2 --dpi-desync-split-seqovl=726 --dpi-desync-fooling=badsum,badseq --dpi-desync-badseq-increment=0 --new
--filter-udp=443 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new
--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new
--filter-tcp=2053,2083,2087,2096,8443 --hostlist-domains=discord.media --dpi-desync=multisplit --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" 