package flixel.addons.display;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxMatrix;
import flixel.math.FlxAngle;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.FlxAssets;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;

using flixel.util.FlxColorTransformUtil;

// TODO: Make blitting more optimized with rotation
// TODO: Fix the hacks when repeatAxis is X or Y
// TODO: Make blitting use batching if the tiles are 8 or more
// TODO: Fix zoom not working properly with blitting when repeatAxis is X or Y

/**
 * Used for showing infinitely scrolling backgrounds.
 * @author George Kurelic (Original concept by Chevy Ray)
 * @author NeeEoo (Added rotation and zoom)
 */
class FlxBackdrop extends FlxSprite
{
	/**
	 * The axes to repeat the backdrop, defaults to XY which covers the whole camera.
	 */
	public var repeatAxes:FlxAxes = XY;

	/**
	 * The gap between repeated tiles, defaults to (0, 0), or no gap.
	 */
	public var spacing(default, null):FlxPoint = FlxPoint.get();

	/**
	 * If true, tiles are pre-rendered to a intermediary bitmap whenever `loadGraphic` is called
	 * or the following properties are changed: camera size camera zoom, `scale.x`, `scale.y`,
	 * `spacing.x`, `spacing.y`, `repeatAxes` or `angle`. If these properties change often, it is recommended to
	 * set `drawBlit` to `false`.
	 *
	 * Note: blitting will disable animations and only show the first frame.
	 */
	public var drawBlit:Bool = FlxG.renderBlit;

	/**
	 * Decides the the size of the blit graphic. Leave as `AUTO` unless you know what you're doing.
	 *
	 * @see flixel.addons.display.FlxBackDrop.BackdropBlitMode
	 */
	public var blitMode:BackdropBlitMode = AUTO;

	/**
	 * The rotation of the of the backdrop, in degrees. Has no effect if `repeatAxes` is `NONE`.
	 */
	public var rotation(default, set):Float = 0.0;

	/**
	 * The zoom of the backdrop.
	 * Acts like .scale.x and .scale.y but is completely unaffected by the origin.
	**/
	public var zoom(default, set):Float = 1.0;

	var _blitOffset:FlxPoint = FlxPoint.get();
	var _blitGraphic:FlxGraphic = null;
	var _prevDrawParams:BackdropDrawParams = {
		graphicKey: null,
		tilesX: -1,
		tilesY: -1,
		scaleX: 0.0,
		scaleY: 0.0,
		spacingX: 0.0,
		spacingY: 0.0,
		repeatAxes: XY,
		angle: 0.0,
		rotation: 0.0,
		zoom: 1.0
	};

	var _cosRotation:Float = 0.0;
	var _sinRotation:Float = 0.0;

	#if !FLX_CNE_FORK
	public var shaderEnabled:Bool = false;
	#end

	/**
	 * Creates an instance of the FlxBackdrop class, used to create infinitely scrolling backgrounds.
	 *
	 * @param   graphic     The image you want to use for the backdrop.
	 * @param   repeatAxes  If the backdrop should repeat on the X axis.
	 * @param   spacingX    Amount of spacing between tiles on the X axis
	 * @param   spacingY    Amount of spacing between tiles on the Y axis
	 */
	public function new(?graphic:FlxGraphicAsset, repeatAxes = XY, spacingX = 0, spacingY = 0)
	{
		super(0, 0, graphic);

		this.repeatAxes = repeatAxes;
		this.spacing.set(spacingX, spacingY);
	}

	override function destroy():Void
	{
		spacing = FlxDestroyUtil.put(spacing);
		_blitOffset = FlxDestroyUtil.put(_blitOffset);
		_blitGraphic = FlxDestroyUtil.destroy(_blitGraphic);

		super.destroy();
	}

	override function draw()
	{
		if (repeatAxes == NONE)
		{
			super.draw();
			return;
		}

		#if FLX_CNE_FORK
		if (isFrameNull)
			checkEmptyFrame();
		#else
		checkEmptyFrame();
		#end

		if (alpha == 0 || _frame.type == FlxFrameType.EMPTY)
			return;

		if (scale.x <= 0 || scale.y <= 0)
			return;

		if (dirty) // rarely
			calcFrame(useFramePixels);

		if (drawBlit)
		{
			drawToLargestCamera();
		}

		for (camera in cameras)
		{
			if (!camera.visible || !camera.exists || !isOnScreen(camera))
				continue;

			if (isSimpleRender(camera))
				drawSimple(camera);
			else
				drawComplex(camera);

			#if FLX_DEBUG
			FlxBasic.visibleCount++;
			#end
		}

		#if FLX_DEBUG
		if (FlxG.debugger.drawDebug)
			drawDebug();
		#end
	}

	/**
	 * Modifies in-place
	**/
	function getRotatedView(view:FlxRect):FlxRect
	{
		if (rotation == 0)
			return view;

		return view.getRotatedBounds(rotation, FlxPoint.weak(view.width / 2, view.height / 2), view);
	}

	/**
	 * Modifies in-place
	**/
	function getZoomedView(view:FlxRect):FlxRect
	{
		if (zoom == 1.0)
			return view;

		final cx = view.x + view.width / 2;
		final cy = view.y + view.height / 2;

		view.x = cx - (view.width / zoom) / 2;
		view.y = cy - (view.height / zoom) / 2;
		view.width /= zoom;
		view.height /= zoom;
		return view;
	}

	override function isOnScreen(?camera:FlxCamera):Bool
	{
		if (repeatAxes == XY)
			return true;

		if (repeatAxes == NONE)
			return super.isOnScreen(camera);

		if (camera == null)
			camera = FlxG.camera;

		var bounds = getScreenBounds(_rect, camera);
		var view = camera.getViewRect();
		view = getRotatedView(view);
		if (repeatAxes.x)
			bounds.x = view.x;
		if (repeatAxes.y)
			bounds.y = view.y;
		view.put();

		return camera.containsRect(bounds);
	}

	function drawToLargestCamera()
	{
		var largest:FlxCamera = null;
		var largestArea = 0.0;
		var view = FlxRect.get();
		for (camera in cameras)
		{
			if (!camera.visible || !camera.exists || !isOnScreen(camera))
				continue;

			camera.getViewRect(view);
			if (view.width * view.height > largestArea)
			{
				largest = camera;
				largestArea = view.width * view.height;
			}
		}
		view.put();

		if (largest != null)
			regenGraphic(largest);
	}

	var hasBeenComplex:Bool = false;

	override function isSimpleRenderBlit(?camera:FlxCamera):Bool
	{
		if (repeatAxes == NONE)
			return super.isSimpleRenderBlit(camera);

		if (hasBeenComplex)
			return true;

		return hasBeenComplex = (super.isSimpleRenderBlit(camera) || drawBlit)
			&& (camera != null ? isPixelPerfectRender(camera) : pixelPerfectRender)
			&& (rotation == 0)
			&& (zoom == 1.0);
	}

	override function drawSimple(camera:FlxCamera):Void
	{
		if (repeatAxes == NONE)
		{
			super.drawSimple(camera);
			return;
		}

		var drawDirect = !drawBlit;
		final graphic = drawBlit ? _blitGraphic : this.graphic;
		final frame = drawBlit ? _blitGraphic.imageFrame.frame : _frame;

		// The distance between repeated sprites, in screen space
		var tileSize = FlxPoint.get(frame.frame.width, frame.frame.height);
		if (drawDirect)
			tileSize.addPoint(spacing);

		getScreenPosition(_point, camera).subtractPoint(offset);
		var tilesX = 1;
		var tilesY = 1;
		if (repeatAxes != NONE)
		{
			var view = camera.getViewRect();
			if (repeatAxes.x)
			{
				final left = modMin(_point.x + frameWidth, tileSize.x, view.left) - frameWidth;
				final right = modMax(_point.x, tileSize.x, view.right) + tileSize.x;
				tilesX = Math.round((right - left) / tileSize.x);
				final origTileSizeX = frameWidth + spacing.x;
				_point.x = modMin(_point.x + frameWidth, origTileSizeX, view.left) - frameWidth;
			}

			if (repeatAxes.y)
			{
				final top = modMin(_point.y + frameHeight, tileSize.y, view.top) - frameHeight;
				final bottom = modMax(_point.y, tileSize.y, view.bottom) + tileSize.y;
				tilesY = Math.round((bottom - top) / tileSize.y);
				final origTileSizeY = frameHeight + spacing.y;
				_point.y = modMin(_point.y + frameHeight, origTileSizeY, view.top) - frameHeight;
			}
		}

		if (drawBlit)
			_point.addPoint(_blitOffset);

		if (FlxG.renderBlit)
			calcFrame(true);

		camera.buffer.lock();

		for (tileX in 0...tilesX)
		{
			for (tileY in 0...tilesY)
			{
				// _point.copyToFlash(_flashPoint);
				_flashPoint.setTo(_point.x + tileSize.x * tileX, _point.y + tileSize.y * tileY);

				if (isPixelPerfectRender(camera))
				{
					_flashPoint.x = Math.floor(_flashPoint.x);
					_flashPoint.y = Math.floor(_flashPoint.y);
				}

				final pixels = drawBlit ? _blitGraphic.bitmap : framePixels;
				camera.copyPixels(frame, pixels, pixels.rect, _flashPoint, colorTransform, blend, antialiasing);
			}
		}

		camera.buffer.unlock();
	}

	override function drawComplex(camera:FlxCamera)
	{
		if (repeatAxes == NONE)
		{
			super.drawComplex(camera);
			return;
		}

		var drawDirect = !drawBlit;
		final graphic = drawBlit ? _blitGraphic : this.graphic;
		final frame = drawBlit ? _blitGraphic.imageFrame.frame : _frame;

		frame.prepareMatrix(_matrix, FlxFrameAngle.ANGLE_0, checkFlipX(), checkFlipY());
		_matrix.translate(-origin.x, -origin.y);

		// The distance between repeated sprites, in screen space
		var tileSize = FlxPoint.get(frame.frame.width, frame.frame.height);

		if (drawDirect)
		{
			tileSize.set((frame.frame.width + spacing.x) * scale.x, (frame.frame.height + spacing.y) * scale.y);

			_matrix.scale(scale.x, scale.y);

			if (bakedRotationAngle <= 0)
			{
				updateTrig();

				if (angle != 0)
					_matrix.rotateWithTrig(_cosAngle, _sinAngle);
			}
		}

		var drawItem = null;
		if (FlxG.renderTile)
		{
			var isColored:Bool = (alpha != 1) || (color != 0xffffff);
			var hasColorOffsets:Bool = (colorTransform != null && colorTransform.hasRGBAOffsets());
			drawItem = camera.startQuadBatch(graphic, isColored, hasColorOffsets, blend, antialiasing, shaderEnabled ? shader : null);
		}
		else
		{
			camera.buffer.lock();
		}

		getScreenPosition(_point, camera).subtractPoint(offset);
		var tilesX = 1;
		var tilesY = 1;
		var pivotX = width / 2;
		var pivotY = height / 2;
		if (repeatAxes != NONE)
		{
			final camView = camera.getViewRect();
			var view = switch (repeatAxes)
			{
				case X: FlxRect.get(camView.x, 0, camView.width, height);
				case Y: FlxRect.get(0, camView.y, width, camView.height);
				default: camView; // XY
			}

			pivotX = view.width / 2;
			pivotY = view.height / 2;

			final oldViewWidth = view.width;
			final oldViewHeight = view.height;
			view = getRotatedView(view);

			// start of hack
			// TODO: fix this properly
			switch (repeatAxes)
			{
				case X:
					final widthIncrease = width * view.width / oldViewWidth;
					view.x -= widthIncrease / 2;
					view.width += widthIncrease;
				case Y:
					final heightIncrease = height * view.height / oldViewHeight;
					view.y -= heightIncrease / 2;
					view.height += heightIncrease;
				default:
			}
			// end of hack

			view = getZoomedView(view);

			final bounds = getScreenBounds(camera);

			if (repeatAxes.x)
			{
				final origTileSizeX = (frameWidth + spacing.x) * scale.x;
				final left = modMin(bounds.right, origTileSizeX, view.left) - bounds.width;
				final right = modMax(bounds.left, origTileSizeX, view.right) + origTileSizeX;
				tilesX = Math.round((right - left) / tileSize.x);
				_point.x = left + _point.x - bounds.x;
			}

			if (repeatAxes.y)
			{
				final origTileSizeY = (frameHeight + spacing.y) * scale.y;
				final top = modMin(bounds.bottom, origTileSizeY, view.top) - bounds.height;
				final bottom = modMax(bounds.top, origTileSizeY, view.bottom) + origTileSizeY;
				tilesY = Math.round((bottom - top) / tileSize.y);
				_point.y = top + _point.y - bounds.y;
			}
			view.put();
			bounds.put();
		}
		_point.addPoint(origin);

		if (drawBlit)
			_point.addPoint(_blitOffset);

		final mat = new FlxMatrix();

		var isPixelPerfect = isPixelPerfectRender(camera);
		var shouldRotate = rotation != 0 && repeatAxes != NONE;
		var shouldZoom = zoom != 1.0 && repeatAxes != NONE;

		for (tileX in 0...tilesX)
		{
			for (tileY in 0...tilesY)
			{
				mat.copyFrom(_matrix);
				mat.translate(_point.x + (tileSize.x * tileX), _point.y + (tileSize.y * tileY));

				if (shouldRotate || shouldZoom)
				{
					mat.translate(-pivotX, -pivotY);
					if (shouldRotate)
						mat.rotateWithTrig(_cosRotation, _sinRotation);
					if (shouldZoom)
						mat.scale(zoom, zoom);
					mat.translate(pivotX, pivotY);
				}

				if (isPixelPerfect)
				{
					mat.tx = Math.floor(mat.tx);
					mat.ty = Math.floor(mat.ty);
				}

				if (FlxG.renderBlit)
				{
					final pixels = drawBlit ? _blitGraphic.bitmap : framePixels;
					camera.drawPixels(frame, pixels, mat, colorTransform, blend, antialiasing, shaderEnabled ? shader : null);
				}
				else
				{
					if (!camera.rotateSprite && camera.angle != 0)
					@:privateAccess {
						mat.translate(-camera.width / 2, -camera.height / 2);
						mat.rotateWithTrig(camera._cosAngle, camera._sinAngle);
						mat.translate(camera.width / 2, camera.height / 2);
					}

					drawItem.addQuad(frame, mat, colorTransform);
				}
			}
		}

		if (FlxG.renderBlit)
			camera.buffer.unlock();
	}

	function getFrameScreenBounds(camera:FlxCamera):FlxRect
	{
		if (drawBlit)
		{
			final frame = _blitGraphic.imageFrame.frame.frame;
			return FlxRect.get(x, y, frame.width, frame.height);
		}

		final newRect = FlxRect.get(x, y);

		if (pixelPerfectPosition)
			newRect.floor();
		final scaledOrigin = FlxPoint.weak(origin.x * scale.x, origin.y * scale.y);
		newRect.x += -Std.int(camera.scroll.x * scrollFactor.x) - offset.x + origin.x - scaledOrigin.x;
		newRect.y += -Std.int(camera.scroll.y * scrollFactor.y) - offset.y + origin.y - scaledOrigin.y;
		if (isPixelPerfectRender(camera))
			newRect.floor();
		newRect.setSize(frameWidth * Math.abs(scale.x), frameHeight * Math.abs(scale.y));
		return newRect.getRotatedBounds(angle, scaledOrigin, newRect);
	}

	function modMin(value:Float, step:Float, min:Float)
	{
		return value - Math.floor((value - min) / step) * step;
	}

	function modMax(value:Float, step:Float, max:Float)
	{
		return value - Math.ceil((value - max) / step) * step;
	}

	function regenGraphic(camera:FlxCamera)
	{
		// The distance between repeated sprites, in screen space
		var tileSize = FlxPoint.get((frameWidth + spacing.x) * scale.x, (frameHeight + spacing.y) * scale.y);

		var view = camera.getViewRect();
		var tilesX = 1;
		var tilesY = 1;
		if (repeatAxes != NONE)
		{
			inline function min(a:Int, b:Int):Int
				return a < b ? a : b;
			view = getRotatedView(view);
			view = getZoomedView(view);
			switch (blitMode)
			{
				case AUTO | SPLIT(1):
					if (repeatAxes.x)
						tilesX = Math.ceil(view.width / tileSize.x) + 1;
					if (repeatAxes.y)
						tilesY = Math.ceil(view.height / tileSize.y) + 1;
				case MAX_TILES(1) | MAX_TILES_XY(1, 1):
				case MAX_TILES(max):
					if (repeatAxes.x)
						tilesX = min(max, Math.ceil(view.width / tileSize.x) + 1);
					if (repeatAxes.y)
						tilesY = min(max, Math.ceil(view.height / tileSize.y) + 1);
				case MAX_TILES_XY(maxX, maxY):
					if (repeatAxes.x)
						tilesX = min(maxX, Math.ceil(view.width / tileSize.x) + 1);
					if (repeatAxes.y)
						tilesY = min(maxY, Math.ceil(view.height / tileSize.y) + 1);
				case SPLIT(portions):
					if (repeatAxes.x)
						tilesX = repeatAxes.x ? Math.ceil(view.width / tileSize.x / portions + 1) : 1;
					if (repeatAxes.y)
						tilesY = repeatAxes.y ? Math.ceil(view.height / tileSize.y / portions + 1) : 1;
			}
		}

		view.put();

		if (matchPrevDrawParams(tilesX, tilesY))
		{
			tileSize.put();
			return;
		}
		setDrawParams(tilesX, tilesY);

		_blitOffset.set(0, 0);
		var graphicSizeX = Math.ceil(tilesX * tileSize.x);
		var graphicSizeY = Math.ceil(tilesY * tileSize.y);
		if (repeatAxes != XY)
		{
			final screenBounds = getScreenBounds();
			final screenPos = getScreenPosition();
			if (!repeatAxes.x)
			{
				graphicSizeX = Math.ceil(screenBounds.width);
				_blitOffset.x = screenBounds.x - screenPos.x;
			}

			if (!repeatAxes.y)
			{
				graphicSizeY = Math.ceil(screenBounds.height);
				_blitOffset.y = screenBounds.y - screenPos.y;
			}
			screenBounds.put();
			screenPos.put();
		}

		if (_blitGraphic == null || (_blitGraphic.width != graphicSizeX || _blitGraphic.height != graphicSizeY))
		{
			if (_blitGraphic != null)
				_blitGraphic.useCount--;
			_blitGraphic = FlxG.bitmap.create(graphicSizeX, graphicSizeY, 0x0, true);
			_blitGraphic.useCount++;
		}

		var pixels = _blitGraphic.bitmap;
		pixels.lock();

		pixels.fillRect(pixels.rect, FlxColor.TRANSPARENT);
		animation.frameIndex = 0;
		calcFrame(true);

		_matrix.identity();
		_matrix.translate(-origin.x, -origin.y);
		_matrix.scale(scale.x, scale.y);
		if (bakedRotationAngle <= 0)
		{
			updateTrig();
			if (angle != 0)
				_matrix.rotateWithTrig(_cosAngle, _sinAngle);
		}

		_matrix.translate(origin.x, origin.y);
		_matrix.translate(-_blitOffset.x, -_blitOffset.y);
		_point.set(_matrix.tx, _matrix.ty);

		// draw extra tiles on the edge in case the image protrudes past the tile
		// TODO: Use 0 buffer when angle is multiple of 90 with centered origin
		final bufferX = repeatAxes.x && angle != 0 ? 1 : 0;
		final bufferY = repeatAxes.y && angle != 0 ? 1 : 0;
		for (tileX in -bufferX...tilesX + bufferX)
		{
			for (tileY in -bufferY...tilesY + bufferY)
			{
				_matrix.tx = _point.x + tileX * tileSize.x;
				_matrix.ty = _point.y + tileY * tileSize.y;
				pixels.draw(framePixels, _matrix);
			}
		}

		pixels.unlock();

		tileSize.put();
	}

	inline function matchPrevDrawParams(tilesX:Int, tilesY:Int)
	{
		return _prevDrawParams.graphicKey == graphic.key
			&& _prevDrawParams.tilesX == tilesX
			&& _prevDrawParams.tilesY == tilesY
			&& _prevDrawParams.scaleX == scale.x
			&& _prevDrawParams.scaleY == scale.y
			&& _prevDrawParams.spacingX == spacing.x
			&& _prevDrawParams.spacingY == spacing.y
			&& _prevDrawParams.repeatAxes == repeatAxes
			&& _prevDrawParams.angle == angle
			&& _prevDrawParams.rotation == rotation
			&& _prevDrawParams.zoom == zoom;
	}

	inline function setDrawParams(tilesX:Int, tilesY:Int)
	{
		_prevDrawParams.graphicKey = graphic.key;
		_prevDrawParams.tilesX = tilesX;
		_prevDrawParams.tilesY = tilesY;
		_prevDrawParams.scaleX = scale.x;
		_prevDrawParams.scaleY = scale.y;
		_prevDrawParams.spacingX = spacing.x;
		_prevDrawParams.spacingY = spacing.y;
		_prevDrawParams.repeatAxes = repeatAxes;
		_prevDrawParams.angle = angle;
		_prevDrawParams.rotation = rotation;
		_prevDrawParams.zoom = zoom;
	}

	function set_rotation(value:Float):Float
	{
		if (value != rotation)
		{
			rotation = value;
			_cosRotation = Math.cos(value * FlxAngle.TO_RAD);
			_sinRotation = Math.sin(value * FlxAngle.TO_RAD);
			dirty = true;
		}
		return value;
	}

	inline function set_zoom(value:Float):Float
	{
		if (value != zoom)
		{
			zoom = value;
			dirty = true;
		}
		return value;
	}
}

enum BackdropBlitMode
{
	/**
	 * Not implemented yet.
	 */
	AUTO;

	/**
	 * Blits a bitmap as big as the specified number of x and y tiles and repeats that.
	 */
	MAX_TILES_XY(x:Int, y:Int);

	/**
	 * Blits a bitmap as big as the specified number of tiles and repeats that.
	 */
	MAX_TILES(tiles:Int);

	/**
	 * Blits enough tiles to cover the screen in multiple draws, for example, if the camera is 10x8
	 * tiles big, SPLIT(2) will draw a blit target 5x4 tiles large and draw it 2x2 times to cover the
	 * stage.
	 */
	SPLIT(portions:Int);
}

@:structInit
class BackdropDrawParams
{
	public var graphicKey:String;
	public var tilesX:Int;
	public var tilesY:Int;
	public var scaleX:Float;
	public var scaleY:Float;
	public var spacingX:Float;
	public var spacingY:Float;
	public var repeatAxes:FlxAxes;
	public var angle:Float;
	public var rotation:Float;
	public var zoom:Float;
}
