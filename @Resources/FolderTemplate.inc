[Rainmeter]
OnRefreshAction=[!KeepOnScreen 0]
OnUnfocusAction=[!CommandMeasure MeasureToggle "ClosePanel()"]

[Variables]
IsOpen=0
OrigX=0
OrigY=0
PanelX=18
PanelY=104
IconOffsetX=0
IconOffsetY=0

[MeasureToggle]
Measure=Script
ScriptFile=#@#Scripts\FolderPopup.lua

[FolderIcon]
Meter=Shape
X=(32 + #IconOffsetX#)
Y=(18 + #IconOffsetY#)
Shape=Rectangle 0,0,48,48,12 | Fill Color 38,44,58,235 | StrokeWidth 1.5 | Stroke Color 255,255,255,40
DynamicVariables=1
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
LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]

[PanelBackground]
Meter=Shape
Group=PanelContent
X=(#PanelX# * #IsOpen#)
Y=(#PanelY# * #IsOpen#)
Shape=Rectangle 0,0,(#PanelWidth# * #IsOpen#),(#PanelHeight# * #IsOpen#),8 | Fill Color 29,33,44,250 | StrokeWidth (#IsOpen#) | Stroke Color 50,58,78,255
Hidden=1
DynamicVariables=1

[PanelTitle]
Meter=String
Group=PanelContent
X=((#PanelX# + 16) * #IsOpen#)
Y=((#PanelY# + 14) * #IsOpen#)
W=((#PanelWidth# - 60) * #IsOpen#)
H=(24 * #IsOpen#)
Text=#FolderName#
FontFace=Segoe UI
FontSize=12
FontWeight=700
FontColor=245,247,255,255
AntiAlias=1
Hidden=1
DynamicVariables=1

[PanelClose]
Meter=String
Group=PanelContent
X=((#PanelX# + #PanelWidth# - 24) * #IsOpen#)
Y=((#PanelY# + 12) * #IsOpen#)
W=(24 * #IsOpen#)
H=(24 * #IsOpen#)
Text=[\x00D7]
FontFace=Segoe UI
FontSize=14
FontColor=175,185,205,255
StringAlign=Center
AntiAlias=1
Hidden=1
LeftMouseUpAction=[!CommandMeasure MeasureToggle "ClosePanel()"]
DynamicVariables=1