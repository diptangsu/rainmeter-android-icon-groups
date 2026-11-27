[Rainmeter]
OnRefreshAction=[!KeepOnScreen 0]
OnUnfocusAction=[!CommandMeasure MeasureToggle "ClosePanel()"]

[Variables]
IsOpen=0
AnimScale=1
AnimAlpha=255
AnimShiftX=0
AnimShiftY=0
SelW=96
SelH=84
OrigX=0
OrigY=0
PanelX=18
PanelY=104
IconOffsetX=0
IconOffsetY=0
HoverX=0
HoverY=0
HoverW=98
HoverH=88
HoverAlpha=0

[MeasureToggle]
Measure=Script
ScriptFile=#@#Scripts\FolderPopup.lua
UpdateDivider=-1

; --- UNIFIED LIQUID GLASS FOLDER SQUIRCLE (48x48) ---
[FolderIcon]
Meter=Shape
X=(32 + #IconOffsetX#)
Y=(18 + #IconOffsetY#)
Shape=Rectangle 0,0,48,48,13 | Fill Color 30,34,44,(Round(185 * #FolderAlphaScale#)) | StrokeWidth 1.2 | Stroke Color 255,255,255,(Round(65 * #FolderAlphaScale#))
Shape2=Rectangle 1,1,46,46,12 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke LinearGradient UnifiedInnerGlow
UnifiedInnerGlow=135 | 255,255,255,(Round(65 * #FolderAlphaScale#)) ; 0.0 | 255,255,255,0 ; 0.6
DynamicVariables=1
MouseActionCursorName=HAND
LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]

[FolderLabel]
Meter=String
X=(56 + #IconOffsetX#)
Y=(68 + #IconOffsetY#)
W=78
H=32
Text=#FolderName#
FontFace=Segoe UI
FontSize=9
FontWeight=400
FontColor=255,255,255,255
StringAlign=Center
StringEffect=Border
FontEffectColor=0,0,0,220
ClipString=2
AntiAlias=1
DynamicVariables=1
MouseActionCursorName=HAND
LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]

; --- ANIMATED LIQUID GLASS POPUP PANEL ---
[PanelBackground]
Meter=Shape
Padding=2,2,2,2
Group=PanelContent
X=((#PanelX# + #AnimShiftX#) * #IsOpen#)
Y=((#PanelY# + #AnimShiftY#) * #IsOpen#)
Shape=Rectangle 0,0,(#PanelWidth# * #AnimScale#),(#PanelHeight# * #AnimScale#),(18 * #AnimScale#) | Fill Color 22,25,34,(Round(232 * #PopupAlphaScale# * #AnimAlpha# / 255)) | StrokeWidth 1.2 | Stroke Color 255,255,255,(Round(55 * #PopupAlphaScale# * #AnimAlpha# / 255))
Shape2=Rectangle 1,1,(Max(0, (#PanelWidth# * #AnimScale#) - 2) * #IsOpen#),(Max(0, (#PanelHeight# * #AnimScale#) - 2) * #IsOpen#),(13 * #AnimScale#) | Fill Color 0,0,0,0 | StrokeWidth (#IsOpen#) | Stroke LinearGradient UnifiedInnerGlow
UnifiedInnerGlow=135 | 255,255,255,(Round(65 * #PopupAlphaScale# * #AnimAlpha# / 255)) ; 0.0 | 255,255,255,0 ; 0.6
Hidden=1
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureToggle "ClearSelection()"]

[HoverHighlight]
Meter=Shape
Group=PanelContent
X=((#PanelX# + #AnimShiftX# + (#HoverX# * #AnimScale#)) * #IsOpen#)
Y=((#PanelY# + #AnimShiftY# + (#HoverY# * #AnimScale#)) * #IsOpen#)
Shape=Rectangle 0,0,(#HoverW# * #AnimScale#),(#HoverH# * #AnimScale#),(10 * #AnimScale#) | Fill Color 255,255,255,(Round(28 * #HoverAlpha# * #AnimAlpha# / 255)) | StrokeWidth 1 | Stroke Color 255,255,255,(Round(55 * #HoverAlpha# * #AnimAlpha# / 255))
Hidden=1
DynamicVariables=1
UpdateDivider=-1

[SelectionHighlight]
Meter=Shape
Group=PanelContent
X=0
Y=0
Shape=Rectangle 0,0,(#SelW# * #AnimScale#),(#SelH# * #AnimScale#),(10 * #AnimScale#) | Fill Color 130,175,255,(Round(32 * #AnimAlpha# / 255)) | StrokeWidth 1.2 | Stroke Color 140,190,255,(Round(155 * #AnimAlpha# / 255))
Hidden=1
DynamicVariables=1

[PanelTitle]
Meter=String
Group=PanelContent
X=((#PanelX# + #AnimShiftX# + (16 * #AnimScale#)) * #IsOpen#)
Y=((#PanelY# + #AnimShiftY# + (14 * #AnimScale#)) * #IsOpen#)
W=((#PanelWidth# - 60) * #AnimScale# * #IsOpen#)
H=(24 * #AnimScale# * #IsOpen#)
Text=#FolderName#
FontFace=Segoe UI
FontSize=12
FontWeight=700
FontColor=245,247,255,#AnimAlpha#
AntiAlias=1
Hidden=1
DynamicVariables=1

[PanelClose]
Meter=String
Group=PanelContent
X=((#PanelX# + #AnimShiftX# + ((#PanelWidth# - 24) * #AnimScale#)) * #IsOpen#)
Y=((#PanelY# + #AnimShiftY# + (12 * #AnimScale#)) * #IsOpen#)
W=(24 * #AnimScale# * #IsOpen#)
H=(24 * #AnimScale# * #IsOpen#)
Text=[\x00D7]
FontFace=Segoe UI
FontSize=14
FontColor=175,185,205,#AnimAlpha#
StringAlign=Center
AntiAlias=1
Hidden=1
MouseActionCursorName=HAND
LeftMouseUpAction=[!CommandMeasure MeasureToggle "ClosePanel()"]
DynamicVariables=1
