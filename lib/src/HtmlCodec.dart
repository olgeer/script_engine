class HtmlCodec {
  final Map<String, String> characterNameMap = {
    " ": "nbsp",
    "<": "lt",
    ">": "gt",
    "&":"amp",
    "\"":"quot",
    "©":"copy",
    "®":"reg",
    "™":"trade",
    "×":"times",
    "÷":"divide"
  };

  Map<String, String> characterNameMap2;

  HtmlCodec(){
    characterNameMap2={};
    characterNameMap.forEach((key, value) {
      characterNameMap2.putIfAbsent(value, () => key);
    });
  }

  String getCharacter(String name)=>characterNameMap2[name]??"";
  String getCharacterByByte(String byteStr){
    try {
      String inputStr=byteStr.substring(1);
      int byteCode;
      if(inputStr.toLowerCase().startsWith("x")){
            byteCode=int.parse(inputStr.substring(1),radix: 16);
          }else {
            byteCode=int.parse(inputStr);
          }
      return String.fromCharCode(byteCode);
    } catch (e) {
      print(e);
      return "";
    }
  }

  String getName(String character)=>characterNameMap[character]!=null?"&${characterNameMap[character]};":character;
  String getByte(String character)=>"&#${character.codeUnits[0].toString()};";

  String decode(String text){
    RegExp escape=RegExp(r'&([#|\w]+);');

    String decoded=text;
    while(escape.hasMatch(decoded)){
      String findEscape=escape.firstMatch(decoded).group(1);
      if(findEscape.startsWith("#")){
        decoded=decoded.replaceFirst(escape, getCharacterByByte(findEscape));
      }else{
        decoded=decoded.replaceFirst(escape, getCharacter(findEscape));
      }
    }
    return decoded;
  }

  String encode(String text,{bool force=false}){
    StringBuffer encoded=StringBuffer();
    for(int i=0;i<text.length;i++){
      if(force)
        encoded.write(getByte(text[i]));
      else
        encoded.write(getName(text[i]));
    }
    return encoded.toString();
  }
}
