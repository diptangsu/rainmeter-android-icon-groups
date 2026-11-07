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

; --- UNIFIED LIQUID GLASS FOLDER SQUIRCLE (48x48) ---
[FolderIcon]
Meter=Shape
X=(32 + #IconOffsetX#)
Y=(18 + #IconOffsetY#)
; Layer 1: Full-body translucent glass gradient + outer specular rim
Shape=Rectangle 0,0,48,48,13 | Fill LinearGradient UnifiedGlass | StrokeWidth 1.2 | Stroke LinearGradient UnifiedRim
; Layer 2: Full-body inner refraction border (no top-bar split)
Shape2=Rectangle 1,1,46,46,12 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke LinearGradient UnifiedInnerGlow
UnifiedGlass=135 | 55,68,94,170 ; 0.0 | 34,42,60,150 ; 0.5 | 20,25,38,180 ; 1.0
UnifiedRim=135 | 255,255,255,180 ; 0.0 | 255,255,255,40 ; 0.5 | 140,180,255,85 ; 1.0
UnifiedInnerGlow=135 | 255,255,255,65 ; 0.0 | 255,255,255,0 ; 0.6
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]

; --- UNIFIED LIQUID GLASS POPUP PANEL ---
[PanelBackground]
Meter=Shape
Group=PanelContent
X=(#PanelX# * #IsOpen#)
Y=(#PanelY# * #IsOpen#)
; Layer 1: Exact same full-body glass gradient + outer specular rim
Shape=Rectangle 0,0,(#PanelWidth# * #IsOpen#),(#PanelHeight# * #IsOpen#),14 | Fill LinearGradient UnifiedGlass | StrokeWidth (#IsOpen# * 1.2) | Stroke LinearGradient UnifiedRim
; Layer 2: Exact same full-body inner refraction border
Shape2=Rectangle 1,1,((#PanelWidth# - 2) * #IsOpen#),((#PanelHeight# - 2) * #IsOpen#),13 | Fill Color 0,0,0,0 | StrokeWidth (#IsOpen#) | Stroke LinearGradient UnifiedInnerGlow
UnifiedGlass=135 | 55,68,94,170 ; 0.0 | 34,42,60,150 ; 0.5 | 20,25,38,180 ; 1.0
UnifiedRim=135 | 255,255,255,180 ; 0.0 | 255,255,255,40 ; 0.5 | 140,180,255,85 ; 1.0
UnifiedInnerGlow=135 | 255,255,255,65 ; 0.0 | 255,255,255,0 ; 0.6
Hidden=1
DynamicVariables=1

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