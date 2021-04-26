String scriptStr='''
{
  "processName": "testProc",
  "globalValue": {
    "url": "http://www.txshuku.la",
    "encoding": "gbk",
    "searchkey": "King"
  },
  "functionDefine": {
    "checkTitle": [
      {
        "action": "selector",
        "type": "dom",
        "script": "title"
      },
      {
        "action": "condition",
        "exp": [
          {
            "expType": "contain",
            "exp": "搜索结果"
          },
          {
            "expType": "contain",
            "exp": "天下书库",
            "relation": "and"
          }
        ],
        "trueProcess": [
          {
            "action": "print",
            "value": "Title匹配成功！"
          }
        ],
        "falseProcess": [
          {
            "action": "print"
          },
          {
            "action": "exit",
            "code": 1
          }
        ]
      }
    ],
    "searchNovel": [
      {
        "action": "getHtml",
        "url": "{url}/modules/article/search.php",
        "queryParameters": {
          "searchtype": "articlename",
          "searchkey": "{searchkey}"
        },
        "method": "get",
        "charset": "gbk"
      },
      {
        "action": "push"
      },
      {
        "action": "callFunction",
        "functionName": "checkTitle"
      },
      {
        "action": "pop"
      },
      {
        "action": "selector",
        "type": "dom",
        "script": ".xs-list"
      },
      {
        "action": "callMultiProcess",
        "multiProcess": [
          {
            "action": "multiSelector",
            "type": "xpath",
            "script": "//ul/li"
          },
          {
            "action": "foreach",
            "eachProcess": [
              {
                "action": "setValue",
                "valueName": "novelName",
                "valueProcess": [
                  {
                    "action": "selector",
                    "type": "xpath",
                    "script": "//p[1]/a/text()"
                  }
                ]
              },
              {
                "action": "setValue",
                "valueName": "writer",
                "valueProcess": [
                  {
                    "action": "selector",
                    "type": "xpath",
                    "script": "//p[2]/span[1]/text()"
                  },
                  {
                    "action": "replace",
                    "from": "作者：",
                    "to": ""
                  }
                ]
              },
              {
                "action": "print",
                "value": "{novelName}-{writer}"
              },
              {
                "action": "getValue",
                "value": "{novelName}-{writer}"
              }
            ]
          }
        ]
      }
    ],
    "downloadNovel": []
  },
  "beginSegment": [
    {
      "action": "callFunction",
      "functionName": "searchNovel"
    }
  ]
}
''';