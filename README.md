Zapret для линукса, работающий на основе конвертирования стратегий предназначенных для винды.

Буду благодарен, если поможете в продвижении, поставив звездочку

**Стратегии, бинарники и листы взяты из [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) и [youtubediscord](https://github.com/youtubediscord/zapret)** 
## Использование

Скачать архив и распаковать в любую директорию. Или можно склонировать:
```
git clone https://github.com/LiGoZoff/zapret-windows-linux.git
```

1. Запустить файл `service.sh`
2. Выполнить конвертацию стратегий, выбрав пункт **`Convert strategies`** в меню (нужно для первого запуска или после добавления новых стратегий)
3. Выбрать нужную стратегию в пункте **`Install Service`** в меню

## Краткие описания файлов

`Service.sh` (адаптированный под линукс service.bat из [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube))

- **`Install Service`** - производится установка уже сконвертированных стратегий, установка стратегии происходит через /opt/[[https://github.com/bol-van/zapret|zapret/]]
- **`Convert strategies`** - происходит конвертация стратегий из папки windows-strategies формата general*.bat
- **`Remove Services`** - выключает запрет и удаляет из автозагрузки
- **`Status Service`** - показывает состояние
- **`Switch Game Filter`** - переключение режима обхода для игр (и других сервисов, использующих UDP и TCP на портах выше 1023).  
  **После переключения требуется перезапуск стратегии.**  
  В скобках указан текущий статус (включено/выключено).

`converter-strategies.sh` - Используется для конвертации стратегий из папки windows-strategies формата general*.bat

Про остальные файлы можно почитать [здесь](https://github.com/Flowseal/zapret-discord-youtube)<-- 

## Решение возможных проблем

Если случилось так, что стратегия работала и перестала работать на следующий день или после перезагрузки.
Попробуйте сделать исполняемым файл /opt/zapret/ipset/create_ipset.sh и запустить его:
```
sudo chmod +x /opt/zapret/ipset/create_ipset.sh
sudo bash /opt/zapret/ipset/create_ipset.sh
```
 После включите и выключите стратегию, чтобы "перезагрузить ipset", при следующем включении стратегии все должно работать.

### Примечания

Для того чтобы полностью удалить запрет, запустите Remove service в service.bat, после можно удалить папку запрета и папку /opt/zapret .

С стратегиями general_Amazon*.bat можно поиграть в Dead by daylight, Fortnite и другие игры с EAC. Античит не будет жаловаться и начнет запускаться.
**На стратегии Amazon не работает Game filter**

В папку windows-strategies можно вставлять другие стратегии в формате general*.bat, но они могут не правильно конвертироваться и не работать.

Zapret будет обновляться вместе с [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube)
