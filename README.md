# 脚本引擎

一个执行json脚本的命令引擎

## 引擎所支持的json脚本说明

脚本结构：
```
{
    "processName": "testProc",
    "globalValue": {
        "url": "https://www.boy5.com",
        "encoding": "utf8",
        "ipage": "1"
    },
    "beginSegment": [
        {
            "action": "callFunction",
            "functionName": "searchNovel",
            "parameters": {
                "page": "{ipage}"
            }
        }
    ],
    "functionDefine": {
        "searchNovel": {
            "parameters": [
                "page"
            ],
            "process": [
                {
                    "action": "getHtml",
                    "url": "{url}/forumdisplay.php",
                    "queryParameters": {
                        "fid": 59,
                        "page": "{page}"
                    },
                    "method": "get",
                    "charset": "gbk"
                },
                {
                    "action": "selector",
                    "type": "dom",
                    "script": "[name=\"moderate\"]"
                }
            ]
        }
    }
}
```
其中 **globalValue** 为全局变量定义，全局生效；  
**beginSegment** 为此脚本的执行入口，引擎将顺序执行脚本直至结束;  
**functionDefine** 为方法定义，允许定义参数，使用**callFunction**命令调用；  
方法定义仍为键值对的方式，键名为方法名，值是方法体，包含两个部分，**parameters** 以及 **process**；  
**parameters** 为参数名数组，可以为空；  
**process** 则为命令队列，按顺序执行；  


命令分为两类，一类是单线任务，一般只有一个字符型的入口参数，以及脚本项，返回结果也是字符型的；
另一类则为多线任务，入口参数为字符串数组，及对应的脚本项；

部分单线命令会内嵌多线命令，也有多线命令内嵌单线命令的情况，后续会进行说明。

字符型参数部分支持嵌套变量，则表示在字符串内可使用"{xxx}"的形式将变量名为xxx的值嵌入字符串中，一个参数可嵌套多个变量，如："{url}/page{ipage}.html"

## 单线命令列表：
---------------------
### 字符串操作  

**print**   日志打印，默认打印value的值到日志；
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|-----|----
value|指定输出格式|字符型|可空|可|可采用{xxx}形式调用参数
```
{
    "action": "print",
    "value": "{url} is print"   //*
}
```

**replace** 字符替换命令，将value值按要求替换
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|-----|----
from | 匹配内容 | 字符型 | 否 | 否 | 可使用正则表单式
to | 替换内容 | 字符型 | 可空 | 可 | 默认为""
```
{
    action": "replace",
    "from": "<(\\S+)[\\S| |\\n|\\r]*?>[^<]*</\\1>",
    "to": ""
}
```

**substring**   取子串命令，对value进行
参数名 | 描述 | 类型 | 可空 | 说明
----|-----|----|----|------
start | 开始位置 | 整形 | 否 | 如为负数则指倒数的位数
end | 结束位置 | 整形 | 可空 | 如为负数则指倒数的位数，当为空时会检测length参数
length | 子串长度 | 整形 | 可空 | 只有当end为空时生效，如也为空则相当于end等于字符串末尾位置
```
{
    "action": "substring",
    "start": 2,  // 为null 则 从0开始，如果为 负数 则从后面算起，如 "abcde" ,-2则指从'd'起
    "end": 10,   // 为null 则 到结尾，当end值小于begin值时，两值对调，如为负数则从开始算起
    "length": 4  // 当end为null时，解释此参数，如亦为null则忽略此逻辑
}
```

**concat**   合并字符串命令，对value进行
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
front | 前字符串 | 字符 | 可空 | 可 | 为空则相对于""
back | 后字符串 | 字符 | 可空 | 可 | 为空则相对于""
```
{
    "action": "concat",
    "front": "<table>",
    "back": "</table>"
}
```

**split**   分割字符串命令，对value进行
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
pattern | 分割字符串 | 字符 | 否 | 可 | 如查无此分割串则返回""
index | 取值索引 | 整形/字符 | 可空 | 否 | 为空则相对于0,当为字符串时仅接受"first"和"last"值
```
{
    "action": "split",
    "pattern": "cid=",
    "index": 1
}
```

**trim**   去除前后空格命令，对value进行
```
{
    "action": "trim"
}
```

**htmlDecode**   对当前value做html标识转换，把&lt;形式转化为"<"
```
{
    "action": "htmlDecode"
}
```

### 变量操作  

**setValue**   保存变量，此命令不会影响当前value
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
valueName | 变量名称 | 字符 | 否 | 否 | 如查无此分割串则返回""
value | 变量值 | 字符 | 可空 | 可 | value为空且则valueProcess为空则保存当前value值
valueProcess | 命令队列 | 命令队列 | 可空 | 否 | value为空且则valueProcess为空则保存当前value值
```
{
    "action": "setValue",
    "valueName": "pageUrl",
    "value":"http://www.163.com", //*
    "valueProcess":[] //*
}
```

**getValue**   获取值到当前value，两个参数不可同时为空
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
exp | 赋值 | 字符 | 可空 | 可 | 优先处理exp参数
value | 变量名 | 字符 | 可空 | 否 | 当exp参数为空时，获取value名的值(逐步弃用)
```
{
    "action": "getValue",
    "value": "url",   //*
    "exp": "{novelName}-{writer}"   //*
}
```

**removeValue**   删除变量，此命令不会影响当前value
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
valueName | 变量名 | 字符 | 否 | 否 | 无
```
{
    "action": "removeValue",
    "valueName": "pageUrl"
}
```

**clearEnv**   清除临时变量集和堆栈，此命令不会影响当前value，不会影响全局变量
```
{
    "action": "clearEnv"
}
```

**push**   当前value入栈，此命令不会影响当前value
```
{
    "action": "push"
}
```

**pop**   弹出最后入栈的值到当前value
```
{
    "action": "pop"
}
```

**json**   将当前value转为json对象，获取某键值
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
keyName | 键值名 | 字符 | 否 | 否 | 无
```
{
    "action": "json",
    "keyName": "pageUrl"
}
```

### 文件操作  

**readFile**   读取文件内容到变量
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
fileName | 文件路径 | 字符 | 否 | 可 | 本地文件的路径
toValue | 变量名 | 字符 | 可 | 可 | 为空时，内容存放到当前value
```
{
    "action": "readFile",
    "fileName": "{basePath}/file1.txt",
    "toValue": "txtfile"
}
```

**saveFile**   保存内容到本地文件
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
fileName | 文件路径 | 字符 | 否 | 可 | 本地文件的路径
saveContent | 保存内容 | 字符 | 否 | 可 | 无
mode | 打开模式 | 字符 | 可 | 否 | 接受"append"和"overwrite"，默认为"append"
```
{
    "action": "saveFile",
    "fileName": "{basePath}/file1.txt",
    "saveContent": "{title}\n\r{content}"
    "mode": "append"
}
```

**saveFile**   保存网络文件内容到本地
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
fileName | 文件路径 | 字符 | 否 | 可 | 本地文件的路径
url | 文件url | 字符 | 否 | 可 | 无
overwrite | 重写模式 | 布尔型 | 可 | 否 | 默认为false
```
{
    "action": "saveUrlFile",
    "fileName": "{basePath}/file1.jpg",
    "url": "http://pic.baidu.com/sample.jpg",
    "overwrite": true    //* 默认为false
}
```

**getHtml**   获取网页到当前value
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
url | 网页url | 字符 | 否 | 可 | 无
method | 请求方式 | 字符 | 可 | 否 | 默认为"get"
charset | 编码方式 | 字符 | 可 | 否 | 默认为"utf8"
headers | 请求头 | 键对 | 可 | 否 | 默认为空对象{}
body | 请求体 | 字符 | 可 | 可 | 支持"get"和"post"，默认为"get"
queryParameters | 请求参数 | 键对 | 可 | 可 | 默认为空对象{}
```
{
    "action": "getHtml",
    "url": "{url}/modules/article/search.php",
    "method": "get",
    "charset": "gbk",
    "queryParameters": {
        "searchtype": "articlename",
        "searchkey": "{searchkey}"
    },
    "headers": {
        "Content-Type": "application/x-www-form-urlencoded"
    },
    "body": "searchtype=all&searchkey={searchkey}",

}
```

### 内容选择器

**selector**    取表达式中的值到value
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
type | 选择器类型 | 字符 | 否 | 否 | 暂时支持"dom"、"xpath"、"regexp"这三种选择器
script | 选择表达式 | 字符 | 否 | 否 | 根据type参数，存放相应选择器的选择表达式
property | 属性值 | 字符 | 可 | 否 | 仅当type为"dom"时有效，可能的值有"innerHtml"、"outerHtml"、"content"等，如果property为空则相当于"innerHtml"值。除了之前列出的可用值外，还可以有其它值，其代码逻辑为`tmp.attributes[ac["property"]]`

范例：  
```
{
    "action": "selector",
    "type": "dom",
    "script": "[property=\"og:novel:book_name\"]",
    "property": "content"
}
{
    "action": "selector",
    "type": "xpath",
    "script": "//p[3]/span[1]/text()"
}
{
    "action": "selector",
    "type": "regexp",
    "script": "<[^>]*>"
}
```

**selectorAt**    取表达式中的值到value，符合表达式的结果有多条时使用
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
type | 选择器类型 | 字符 | 否 | 否 | 暂时支持"dom"、"xpath"、"regexp"这三种选择器
script | 选择表达式 | 字符 | 否 | 否 | 根据type参数，存放相应选择器的选择表达式
property | 属性值 | 字符 | 可 | 否 | 仅当type为"dom"时有效，可能的值有"innerHtml"、"outerHtml"、"content"等，如果property为空则相当于"innerHtml"值。除了之前列出的可用值外，还可以有其它值，其代码逻辑为`tmp.attributes[ac["property"]]`
index | 取值位置 | 整形 | 否 | 否 | 多个结果中的第几个，位置从0开始算

范例：
```
{
    "action": "selectorAt",
    "type": "dom",
    "script": "div.book_list",
    "index": 1
}
```

### 非顺序执行

**for**    通过循环将值放置到临时变量中
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
valueName | 临时变量名 | 字符 | 否 | 否 | 通过循环将值放置到临时变量中
type | 范围类型 | 字符 | 否 | 否 | 暂时支持"list"、"range"这两种
range | 取值范围 | 整形数组/字符串 | 可 | 否 | 为字符串类型时，格式为"2-10"这样，用"-"分割开，代表2、3、4...10，共9个数
list | 取值列表 | 整形数组/字符串 | 可 | 否 | 为字符串类型时，格式为"2,10"这样，用","分割开，代表2和10
loopProcess | 循环执行 | 命令队列 | 否 | 否 | 将值存放到valueName变量中后，执行loopProess单线命令队列
返回结果数组转换为以","分割的字符串后返回。

范例：
```
{
    "action": "for",
    "valueName": "ipage",
    "type": "list",
    "range": [1,10],     // as String "1-10"
    "list": [1,2,4,5,7], // as String "1,2,3,4"
    "loopProcess": []
}
```

**condition**    通过循环将值放置到临时变量中
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
exps | 条件表达式集 | 表达式数组 | 否 | 否 | 表达式结构见后文
trueProcess | 真单线命令序列 | 命令序列 | 可 | 否 | 无
falseProcess | 假单线命令序列 | 命令序列 | 可 | 否 | 无

范例：
```
{
    "action": "condition",
    "exps": [{
        "expType": "contain",
        "exp": "搜索结果",
        "source":"{title}"
    }],
    "trueProcess": [],
    "falseProcess": []
}
```


### 调用方法  

**callFunction**    调用子函数
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
functionName | 函数名 | 字符 | 否 | 否 | 函数名无效时报错
parameters | 输入参数 | 键值对 | 可 | 可 | 无
范例：
```
{
    "action": "callFunction",
    "functionName": "getPage",
    "parameters": {
        "page": "{ipage}"
    }
}
```

**callMultiProcess**    调用多线命令序列
参数名 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
multiBuilder | 参数组构建 | 多线命令序列 | 可 | | 为空时，用values作为参数
values | 输入参数组 | 字符串数组 | 可 | 可 | 当multiBuilder及values皆为空时，用[value]作为参数
multiProcess | 处理命令 | 多线命令序列 | 否 | 否 | 无
返回结果数组的toString形式，如"abc,ssd,03"
范例：
```
{
    "action": "callMultiProcess",
    "multiBuilder":[
        {
            "action": "fill",
            "valueName": "ipage",
            "type": "list",
            "list": [1,2,4,5,7],
            "exp": "{url}_{ipage}"
        }
    ],
    "values": [],
    "multiProcess": []
}
```

### 结束命令

**break**    终止当前命令序列  
范例：
```
{
    "action": "break"
}
```

**exit**    退出程序，当前进程关闭  
范例：
```
{
    "action": "exit"
}
```

### 扩展命令  
引擎支持命令拓展，可在初始化引擎时，设置extendSingleAction方法即可实现。
extendSingleAction方法的定义为`Future<String?> Function(String? value, dynamic ac,{String? debugId, bool? debugMode})`


## 多线命令列表  



## 条件表达式  


条件表达式为在需要判断条件时使用，表达式的常见格式如下：
属性 | 描述 | 类型 | 可空 | 嵌套变量 | 说明
----|----|----|----|----|----
expType | 表单式类型 | 字符 | 否 | 否 | 现在支持的表单式类型有"isNull"、"isEmpty"、"in"、"compare"、"contain"、"not"
exp | 表单式 | 字符/字符串数组 | | 可 | 除"isNull"、"isEmpty"、"not"外，此字段不可空
source | 源内容 | 字符 | 可 | 可 | 与条件表达式运算的源内容，如为空则当前value为源内容
not | 非操作 | 布尔 | 可 | 否 | 此条件表达式最终结果是否取非操作
relation | 条件关系 | 字符 | 可 | 否 | 与上一条件的逻辑关系，支持"and"和"or"
```
{
    "expType": "in",
    "exp": "jpg,png,jpeg,gif,bmp",
    "not": true
}
{
    "expType": "compare",
    "exp": "成功删除"
}
{
    "expType": "contain",
    "exp": "viewthread.php",
    "source": "{url}", //* 存在则优先处理
    "not": true,
    "relation": "and"
}
```