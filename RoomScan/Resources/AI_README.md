# {{PROJECT_NAME}}：房屋白模与尺寸数据

这是用 iPhone LiDAR（Apple RoomPlan）扫描得到的空房间白模，用来在 Blender 里做室内建模。
扫描时间 {{DATE}}，共 {{ROOM_COUNT}} 个房间，总面积约 {{TOTAL_AREA}} ㎡。

## 文件说明

| 文件 | 用途 |
|---|---|
| `scene.json` | **最权威的结构化数据**：房间、墙、门窗、固定设施、备注，单位米 |
| `build_whitebox.py` | Blender 脚本，读 `scene.json` 按真实尺寸重建白模（推荐用这个） |
| `whitebox.obj` / `.mtl` | 同一个白模的 OBJ 版本，可以直接导入 Blender |
| `whitebox.usda` | 同一个白模的 USD 版本（Z 轴朝上、单位米，Blender 可直接导入） |
| `roomplan_original.usdz` | Apple RoomPlan 的原始参数化模型，带家具，仅供参考 |
| `floorplan.png` / `.pdf` | 俯视尺寸平面图，单位 mm |
| `photos/` | 现场照片。`AUTO_` 开头的是扫描时自动拍的，其余是手动拍的；位置和朝向见 `scene.json` 的 `sitePhotos` |

## 坐标系与单位

- 单位：米（平面图和备注里的数字是毫米）
- 右手坐标系，**Z 轴朝上**，和 Blender 一致；地面 z = 0
- `whitebox.obj` 用 Blender 默认导入设置（Forward -Z，Up Y）导入后，坐标和 `scene.json` 完全一致

## scene.json 字段要点

- `rooms[].floorPolygon`：地面轮廓（逆时针），`height` 是层高
- `walls[].start / end`：**房间内侧墙面**所在的线；`thickness` 向 `outward`（房间外侧）挤出
- `walls[].height`：墙高。**比所在房间层高低的墙，通常说明那里有梁或吊顶**，高度就是梁底/吊顶底离地的高度（扫描没有单独识别梁，只是近似）
- `walls[].measuredLength`：用户用卷尺实测的墙长。**有值时以实测值为准**
- `openings[]`：门窗洞口。`centerOffset` 是洞口中心到墙 `start` 的距离，`sillHeight` 是离地高度
  - `style`：用户标注的样式。门：`swingDoor` 平开门、`slidingDoor` 推拉门、`foldingDoor` 折叠门；
    窗：`casementWindow` 平开窗、`slidingWindow` 推拉窗、`fixedWindow` 固定窗、`awningWindow` 上悬窗。没有这个字段表示用户还没确认
  - `hinge`：门轴 / 合页在哪边（`left` / `right`），按「站在房间里、面朝这面墙」来看，也就是从 `outward` 的反方向看过去
  - `opensOutward`：平开门是否往房间外开，`false` 或没有表示往里开
- `fixtures[]`：马桶、洗手盆、灶台等固定设施的位置。它们决定**下水、排烟、电位**，做设计时不要随意移动
- `annotations[]`：用户备注（note）和测距（measurement），`photos` 是照片路径
- `sitePhotos[]`：现场照片（扫描时自动拍的，`isAuto: true`，以及手动拍的）。每张都有拍摄相机的 `cameraPosition`、
  `cameraDirection`、`cameraUp`、`verticalFov`（竖拍画面的垂直视角，度），以及拍到的房间 `roomId` 和墙 `wallId`。
  想知道某面墙、某个房间现场长什么样（墙面颜色、地面材质、管线、开关插座位置），就看对应的照片。
  `build_whitebox.py` 会给每张照片建一台同角度的相机（Photo_Cameras 集合），照片设为相机背景，可以和白模叠在一起对照

## 房间一览

{{ROOM_TABLE}}

## 用户备注

{{ANNOTATIONS}}

## 实测值

{{MEASURED}}

## 建议的工作流程

1. 在 Blender 里运行：`blender --background --python build_whitebox.py -- scene.json whitebox.blend`
   或者直接导入 `whitebox.obj`
2. 先读一遍上面的备注和 `photos/`，弄清楚用户的需求和现场情况
3. 在白模里做室内设计（墙面、地面、吊顶、柜体、家具），**不要改动墙体位置和门窗洞口**
4. 卫生间、厨房的设计要围绕 `fixtures` 里的位置来做

## 已知误差

- LiDAR 扫描的墙长误差一般在几厘米以内；玻璃、镜子和杂物多的地方误差会大一些
- 墙厚是默认值（120 mm），不是测量值
- `isCurved: true` 的墙是弧形墙，这里近似成了直线
