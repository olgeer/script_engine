# script_engine

a json script engine to do anything

## Getting Started

This project is a starting point for a Dart
[package](https://flutter.dev/developing-packages/),
a library module containing code that can be shared easily across
multiple Flutter or Dart projects.

For help getting started with Flutter, view our 
[online documentation](https://flutter.dev/docs), which offers tutorials, 
samples, guidance on mobile development, and a full API reference.

脚本结构：
'''
{
    "processName": "testProc",
    "globalValue": {
        "url": "https://www.boy5.com",
        "encoding": "utf8",
        "searchkey": "围城"
    },
    "beginSegment": [
        {
            "action": "getValue",
            "exp": "{android.applicationDir} - hello world"
        },
        {
            "action": "print"
        },
        {
            "action": "getHtml",
            "url": "{url}/modules/article/search.php?searchkey={searchkey}",
            "method": "get",
            "charset": "utf8"
        },
        {
            "action": "print"
        }
    ]
}
'''

其中 beginSegment 为此脚本的执行入口，引擎将顺序执行脚本直至结束。
globalValue 为全局变量定义，全局生效。

脚本分为两类，一类是单线任务，一般只有一个字符型的入口参数，以及脚本项，返回结果也是字符型的；
另一类则为多线任务，入口参数为字符串数组，及对应的脚本项；

部分单线命令会内嵌多线命令，也有多线命令内嵌单线命令的情况，后续会进行说明。

单线命令列表：
print   日志打印，默认打印value的值到日志；
        如使用value制定打印内容，则按指定内容输出到日志，可采用{}形式调用参数
'''
{
    "action": "print",
    "value": "{url} is print"   //*
}
'''

replace 字符替换命令，将value值按要求替换
        from 匹配内容，字符型，可使用正则表单式
        to 替换内容，字符型
'''
{
    action": "replace",
    "from": "<(\\S+)[\\S| |\\n|\\r]*?>[^<]*</\\1>",
    "to": ""
}
'''

substring   取子串命令，对value进行
        start 开始位置，整形，如为负数则指倒数的位数
        end 结束位置，整形，可空，如为负数则指倒数的位数，当为空时会检测length参数
        length 子串长度，可空，只有当end为空时生效，如也为空则相当于end等于字符串末尾位置
'''
{
    "action": "substring",
    "start": 2,  // 为null 则 从0开始，如果为 负数 则从后面算起，如 "abcde" ,-2则指从'd'起
    "end": 10,   // 为null 则 到结尾，当end值小于begin值时，两值对调，如为负数则从开始算起
    "length": 4  // 当end为null时，解释此参数，如亦为null则忽略此逻辑
}
'''

多线命令列表：