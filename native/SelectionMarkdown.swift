import Foundation
import SwiftUI

struct LabMarkdownBlock:Identifiable {
 enum Kind{case paragraph,heading,list,quote,code,table,rule}
 let id:Int
 let kind:Kind
 var text=AttributedString()
 var marker=""
 var level=0
 var rows:[[AttributedString]]=[]
}

/// Local text-only rendering. No HTML/WebView, remote images or network fetches.
/// The source answer remains intact; display and clean-text copy share cached blocks.
enum LabAnswerMarkdown {
 private static let code=try! NSRegularExpression(pattern:#"(`+)[\s\S]*?\1"#)
 private static let bold=try! NSRegularExpression(pattern:#"(?s)(?<!\\)(\*\*|__)(.+?)\1"#)
 private static let heading=try! NSRegularExpression(pattern:#"^(#{1,6})\s+(.+?)(?:\s+#+)?$"#)
 private static let list=try! NSRegularExpression(pattern:#"^(\s*)([-+*]|[0-9]+[.)])\s+(.+)$"#)
 private static func capture(_ expression:NSRegularExpression,_ text:String)->[String]? {
  guard let match=expression.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else{return nil}
  return (0..<match.numberOfRanges).map{Range(match.range(at:$0),in:text).map{String(text[$0])} ?? ""}
 }
 private static func repaired(_ source:String)->String {
  var result=source
  for m in bold.matches(in:source,range:NSRange(source.startIndex...,in:source)).reversed(){
   guard let range=Range(m.range,in:result),let content=Range(m.range(at:2),in:source),let token=Range(m.range(at:1),in:source) else{continue}
   let value=source[content].trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"\n",with:" ")
   result.replaceSubrange(range,with:String(source[token])+value+String(source[token]))
  }
  return result
 }
 private static func closePendingStrong(_ source:String)->String {
  let characters=Array(source);var cursor=0,pending:String?=nil,codeTicks=0
  while cursor<characters.count {
   if characters[cursor]=="\\"{cursor+=2;continue}
   if characters[cursor]=="`" {
    var count=1;while cursor+count<characters.count,characters[cursor+count]=="`"{count+=1}
    if codeTicks==0{codeTicks=count}else if codeTicks==count{codeTicks=0};cursor+=count;continue
   }
   if codeTicks==0,cursor+1<characters.count,characters[cursor]==characters[cursor+1],characters[cursor]=="*" || characters[cursor]=="_" {
    let token=String(repeating:String(characters[cursor]),count:2)
    if pending==token{pending=nil}
    else if pending==nil,cursor+2<characters.count,!characters[cursor+2].isWhitespace,
      cursor==0 || characters[cursor-1].isWhitespace || characters[cursor-1].isPunctuation{pending=token}
    cursor+=2;continue
   }
   cursor+=1
  }
  return source+(pending ?? "")
 }
 static func inline(_ source:String)->AttributedString {
  guard source.contains(where:{"*_`[~".contains($0)}) else{return AttributedString(source)}
  // Keep inline code and escaped punctuation literal while repairing model output.
  var normalized="",cursor=source.startIndex
  for m in code.matches(in:source,range:NSRange(source.startIndex...,in:source)) {
   guard let range=Range(m.range,in:source) else{continue}
   normalized += repaired(String(source[cursor..<range.lowerBound]))+source[range];cursor=range.upperBound
  }
  normalized += repaired(String(source[cursor...]))
  normalized=closePendingStrong(normalized)
  var value=(try? AttributedString(markdown:normalized,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace,failurePolicy:.returnPartiallyParsedIfPossible))) ?? AttributedString(source)
  for run in value.runs {
   if let link=run.link,!(["https","http"].contains(link.scheme?.lowercased() ?? "")){value[run.range].link=nil}
  }
  return value
 }
 private static func cells(_ line:String)->[String]{
  var text=line.trimmingCharacters(in:.whitespaces)
  if text.hasPrefix("|"){text.removeFirst()};if text.hasSuffix("|"){text.removeLast()}
  return text.components(separatedBy:"|").map{$0.trimmingCharacters(in:.whitespaces)}
 }
 static func blocks(_ source:String)->[LabMarkdownBlock] {
  let lines=source.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n")
  var result:[LabMarkdownBlock]=[],paragraph:[String]=[],i=0
  func add(_ kind:LabMarkdownBlock.Kind,_ text:String,marker:String="",level:Int=0){result.append(.init(id:result.count,kind:kind,text:kind == .code ? AttributedString(text):inline(text),marker:marker,level:level))}
  func flush(){if !paragraph.isEmpty{add(.paragraph,paragraph.joined(separator:"\n"));paragraph=[]}}
  while i<lines.count {
   let line=lines[i],trim=line.trimmingCharacters(in:.whitespaces)
   if trim.hasPrefix("```") || trim.hasPrefix("~~~") {
    flush();let fence=String(trim.prefix(3));var code:[String]=[];i+=1
    while i<lines.count && !lines[i].trimmingCharacters(in:.whitespaces).hasPrefix(fence){code.append(lines[i]);i+=1}
    add(.code,code.joined(separator:"\n"));i+=1;continue
   }
   if trim.isEmpty{flush();i+=1;continue}
   if trim.count>=3 && (["-","*","_"].contains(String(trim.first!))) && Set(trim.filter{!$0.isWhitespace}).count==1{flush();add(.rule,"");i+=1;continue}
   if let h=capture(heading,trim){flush();add(.heading,h[2],level:h[1].count);i+=1;continue}
   if i+1<lines.count,line.contains("|") {
    let columns=cells(line),separators=cells(lines[i+1])
    if columns.count>1,columns.count<=6,separators.count==columns.count,separators.allSatisfy({$0.filter{$0=="-"}.count>=3 && $0.allSatisfy{"-: ".contains($0)}}) {
     flush();var rows=[columns.map(inline)];i+=2
     while i<lines.count,lines[i].contains("|"),cells(lines[i]).count==columns.count{rows.append(cells(lines[i]).map(inline));i+=1}
     result.append(.init(id:result.count,kind:.table,rows:rows));continue
    }
   }
   if let item=capture(list,line){flush();let marker=["-","+","*"].contains(item[2]) ? "•":item[2];add(.list,item[3],marker:marker,level:min(3,item[1].count/2));i+=1;continue}
   if trim.hasPrefix("> "){flush();add(.quote,String(trim.dropFirst(2)));i+=1;continue}
   paragraph.append(line);i+=1
  }
  flush();return result
 }
 static func plainText(_ blocks:[LabMarkdownBlock])->String {
  blocks.compactMap{block->String? in
   switch block.kind {
   case .rule:return nil
   case .list:return block.marker+" "+String(block.text.characters)
   case .table:return block.rows.map{$0.map{String($0.characters)}.joined(separator:"\t")}.joined(separator:"\n")
   default:return String(block.text.characters)
   }
  }.joined(separator:"\n\n")
 }
}

struct SelectionMarkdownView:View {
 let blocks:[LabMarkdownBlock]
 var body:some View {
  VStack(alignment:.leading,spacing:10){
   ForEach(blocks){block in
    switch block.kind {
    case .heading:Text(block.text).font(.system(size:block.level==1 ? 17:15,weight:.semibold)).padding(.top,block.id==0 ? 0:4)
    case .list:HStack(alignment:.top,spacing:8){Text(block.marker).foregroundStyle(Color(white:0.65)).frame(minWidth:12,alignment:.leading);Text(block.text).frame(maxWidth:.infinity,alignment:.leading)}.padding(.leading,CGFloat(block.level)*12)
    case .quote:HStack(alignment:.top,spacing:10){Rectangle().fill(Color(white:0.35)).frame(width:2);Text(block.text).foregroundStyle(Color(white:0.72)).frame(maxWidth:.infinity,alignment:.leading)}.fixedSize(horizontal:false,vertical:true)
    case .code:Text(block.text).font(.system(size:12,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading).padding(10).background(Color(white:0.08),in:RoundedRectangle(cornerRadius:8))
    case .rule:Rectangle().fill(Color(white:0.22)).frame(height:1).padding(.vertical,2)
    case .table:
     VStack(spacing:0){ForEach(block.rows.indices,id:\.self){row in
      HStack(alignment:.top,spacing:12){ForEach(block.rows[row].indices,id:\.self){column in Text(block.rows[row][column]).fontWeight(row==0 ? .semibold:.regular).frame(maxWidth:.infinity,alignment:.leading)}}.padding(8)
       .background(row==0 ? Color(white:0.12):Color.clear)
      if row<block.rows.count-1{Rectangle().fill(Color(white:0.2)).frame(height:0.5)}
     }}.background(Color(white:0.06),in:RoundedRectangle(cornerRadius:8)).clipShape(RoundedRectangle(cornerRadius:8))
    case .paragraph:Text(block.text).frame(maxWidth:.infinity,alignment:.leading)
    }
   }
  }.font(.system(size:14)).lineSpacing(4).textSelection(.enabled).tint(Color(white:0.9))
 }
}
