import Foundation
import AppKit

extension Engine {
  static func videoDisplaySize(_ info:[String:Any])->CGSize {
    let streams=info["streams"] as? [[String:Any]] ?? []
    guard let stream=streams.first(where:{$0["codec_type"] as? String == "video"}) else {return CGSize(width:1,height:1)}
    var w=stream["width"] as? Int ?? 1,h=stream["height"] as? Int ?? 1
    let side=stream["side_data_list"] as? [[String:Any]] ?? []
    let rotation=(side.first(where:{$0["rotation"] != nil})?["rotation"] as? NSNumber)?.intValue ?? Int((stream["tags"] as? [String:String])?["rotate"] ?? "0") ?? 0
    if abs(rotation)%180 == 90 {swap(&w,&h)}
    return CGSize(width:w,height:h)
  }

  func moduleMedia(_ url:URL,action:String,stage:URL,options o:Options) throws -> URL {
    let video=Family.of(url) == .video
    let ext=action == "visualize" ? "mp4" : url.pathExtension.lowercased()
    let destination=output(url,ext,stage,suffix:"-\(action)")
    let info=try probe(url),streams=info["streams"] as? [[String:Any]] ?? []
    let hasAudio=streams.contains {$0["codec_type"] as? String == "audio"}
    var args=["-i",url.path],af:[String]=[],vf:[String]=[]
    switch action {
    case "normalize":
      af=["loudnorm=I=\(o.volume):TP=\(o.truePeak):LRA=\(o.loudnessRange)"]
    case "channels":
      let channels=(streams.first {$0["codec_type"] as? String == "audio"})?["channels"] as? Int ?? 1
      let stereo=channels>1
      let right=stereo ? "c1" : "c0"
      if o.previewChannel == "L" {af=["pan=mono|c0=\(o.left)*c0"]}
      else if o.previewChannel == "R" {af=["pan=mono|c0=\(o.right)*\(right)"]}
      else if o.channels == 1 {af=["pan=mono|c0=\(o.left/2)*c0+\(o.right/2)*\(right)"]}
      else {af=["pan=stereo|c0=\(o.left)*c0|c1=\(o.right)*\(right)"]}
    case "trim":
      let total=try mediaDuration(url)
      guard o.start>=0,o.duration>0,o.start+o.duration<=total+0.1 else {throw ClementineError("L’intervalle dépasse la durée du média")}
      args=["-ss",String(o.start),"-i",url.path,"-t",String(o.duration)]
      if o.trimSilence {af=["silenceremove=start_periods=1:start_duration=0:start_threshold=\(o.silenceThreshold)dB,areverse,silenceremove=start_periods=1:start_duration=0:start_threshold=\(o.silenceThreshold)dB,areverse"]}
    case "speed":
      if video {vf=["setpts=PTS/\(o.speed)"]}
      if hasAudio {
        var rate=o.speed
        while rate>2 {af.append("atempo=2");rate/=2}
        while rate<0.5 {af.append("atempo=0.5");rate*=2}
        af.append("atempo=\(rate)")
      }
    case "bleep":
      guard !o.marks.isEmpty else {throw ClementineError("Ajoutez une plage de bleep")}
      let duration=try mediaDuration(url)
      let ranges=try validatedRanges(o.marks,duration:duration)
      let condition=ranges.map {"between(t,\($0.0),\($0.1))"}.joined(separator:"+")
      args += ["-f","lavfi","-i","sine=frequency=1000:sample_rate=48000:duration=\(duration)","-filter_complex","[0:a]volume=0:enable='\(condition)'[a];[1:a]volume='if(\(condition),0.15,0)':eval=frame[b];[a][b]amix=inputs=2:duration=first:normalize=0[out]","-map","0:v?","-map","[out]"]
    case "redact":
      guard !o.marks.isEmpty else {throw ClementineError("Ajoutez une zone de caviardage")}
      let duration=try mediaDuration(url)
      _=try validatedRanges(o.marks,duration:duration)
      let size=Self.videoDisplaySize(info)
      let width=Int(size.width),height=Int(size.height)
      var filters:[String]=[],previous="0:v"
      for (index,mark) in o.marks.enumerated() {
        guard mark.x>=0,mark.y>=0,mark.width>0,mark.height>0,mark.x+mark.width<=1.0001,mark.y+mark.height<=1.0001 else {throw ClementineError("Zone hors de l’image")}
        let x=max(0,Int(mark.x*Double(width))),y=max(0,Int(mark.y*Double(height)))
        let w=min(width-x,max(2,Int(mark.width*Double(width)))),h=min(height-y,max(2,Int(mark.height*Double(height))))
        let output="r\(index)",enable="between(t,\(mark.start),\(mark.end))"
        if mark.blur {
          filters.append("[\(previous)]split=2[base\(index)][crop\(index)]")
          filters.append("[crop\(index)]crop=\(w):\(h):\(x):\(y),boxblur=luma_radius=\(max(1,min(12,min(w,h)/4))):luma_power=2[blur\(index)]")
          filters.append("[base\(index)][blur\(index)]overlay=\(x):\(y):enable='\(enable)'[\(output)]")
        } else {
          guard mark.color.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil else {throw ClementineError("Couleur invalide")}
          filters.append("[\(previous)]drawbox=x=\(x):y=\(y):w=\(w):h=\(h):color=0x\(mark.color.dropFirst()):t=fill:enable='\(enable)'[\(output)]")
        }
        previous=output
      }
      args += ["-filter_complex",filters.joined(separator:";"),"-map","[\(previous)]","-map","0:a?"]
    case "visualize":
      let ratio=Self.ratio(o.visualizerShape) ?? 16/9
      let width=ratio<1 ? 720 : 1280,height=Int(Double(width)/ratio)/2*2
      if o.visualizerStyle == "Still Image" {
        guard fm.fileExists(atPath:o.backgroundImage) else {throw ClementineError("Choisissez une image pour le visualiseur")}
        args=["-loop","1","-i",o.backgroundImage,"-i",url.path,"-vf","scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2,format=yuv420p","-map","0:v","-map","1:a","-c:v","libx264","-c:a","aac","-tune","stillimage","-shortest",destination.path]
      } else {
        args += ["-filter_complex","[0:a]showwaves=s=\(width)x\(height):mode=cline:colors=0xed7444:rate=30,format=yuv420p[v]","-map","[v]","-map","0:a","-c:v","libx264","-c:a","aac","-shortest",destination.path]
      }
      try ff(args);return destination
    default:throw ClementineError("Module non pris en charge")
    }
    if !vf.isEmpty {args += ["-vf",vf.joined(separator:",")]}
    if !af.isEmpty {args += ["-af",af.joined(separator:",")]}
    try ff(args+mediaEncoding(ext,o:o)+[destination.path]);return destination
  }
  func moduleSplit(_ url:URL,stage:URL,options o:Options) throws -> URL {
    let duration=try mediaDuration(url),points=try numbers(o.times)
    let boundaries=[0]+points+[duration]
    guard boundaries == boundaries.sorted(),Set(boundaries).count==boundaries.count,boundaries.allSatisfy({$0>=0 && $0<=duration}) else {throw ClementineError("Points de division invalides")}
    let folder=output(url,"",stage,suffix:"-clips").deletingPathExtension()
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    var segments:[URL]=[]
    for i in 0..<boundaries.count-1 where !o.splitRemoved.contains(i) {
      let file=folder.appendingPathComponent("Clip \(i+1).mp4")
      try ff(["-ss",String(boundaries[i]),"-i",url.path,"-t",String(boundaries[i+1]-boundaries[i])]+mediaEncoding("mp4",o:o)+[file.path])
      segments.append(file)
    }
    guard !segments.isEmpty else {throw ClementineError("Conservez au moins un segment")}
    if o.splitExportMode == "Merged" {
      if segments.count == 1 {let destination=output(url,"mp4",stage,suffix:"-split");try fm.copyItem(at:segments[0],to:destination);return destination}
      return try join(segments,stage:stage,o:o)
    }
    return folder
  }
  func validatedRanges(_ marks:[ModuleMark],duration:Double) throws -> [(Double,Double)] {
    try marks.map {mark in
      guard mark.start.isFinite,mark.end.isFinite,mark.start>=0,mark.end>mark.start,mark.end<=duration+0.1 else {throw ClementineError("Plage temporelle hors du média")}
      return (mark.start,min(duration,mark.end))
    }
  }
}
