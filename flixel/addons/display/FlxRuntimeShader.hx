package flixel.addons.display;

#if (nme || flash)
	#if (FLX_NO_COVERAGE_TEST && !(doc_gen))
		#error "FlxRuntimeShader isn't available with nme or flash."
	#end
#else
import flixel.graphics.tile.FlxGraphicsShader;
#end
#if lime
import lime.utils.Float32Array;
#end
import openfl.display.BitmapData;
import openfl.display.ShaderInput;
import openfl.display.ShaderParameter;
import openfl.utils.GLSLSourceAssembler;

/**
 * An wrapper for Flixel/OpenFL's shaders, which takes fragment and vertex source
 * in the constructor instead of using macros, so it can be provided data
 * at runtime (for example, when using mods).
 *
 * HOW TO USE:
 * 1. Create an instance of this class, passing the text of the `.frag` and `.vert` files.
 *    Note that you can set either of these to null (making them both null would make the shader do nothing???).
 * 2. Use `flxSprite.shader = runtimeShader` to apply the shader to the sprite.
 * 3. Use `runtimeShader.setFloat()`, `setBool()` etc. to modify any uniforms.
 * 4. Use `setBitmapData()` to add additional textures as `sampler2D` uniforms
 *
 * @author MasterEric
 * @see https://github.com/openfl/openfl/blob/develop/src/openfl/utils/_internal/ShaderMacro.hx
 * @see https://dixonary.co.uk/blog/shadertoy
 */
class FlxRuntimeShader extends FlxGraphicsShader
{
	private var _cacheProgramIdDefault:String;
	private var _glFragmentSourceDefault:String;
	private var _glVertexSourceDefault:String;
	private var _fragmentFilePath:Null<String>;
	private var _vertexFilePath:Null<String>;

	/**
	 * Constructs a GLSL shader.
	 * NOTE: The shader won't be able to be properly cached, it is recommended
	 *  to use fromFile instead.
	 * @param fragmentSource The fragment shader source.
	 * @param vertexSource The vertex shader source.
	 * @param glslVersion The shader glsl version.
	 */
	public function new(?fragmentSource:String, ?vertexSource:String, ?glslVersion:String):Void
	{
		super();

		_cacheProgramIdDefault = __cacheProgramId;
		_glFragmentSourceDefault = __glFragmentSourceRaw;
		_glVertexSourceDefault = __glVertexSourceRaw;

		if (glslVersion != null) __glVersionRaw = glslVersion;
		if (fragmentSource != null) __glFragmentSourceRaw = fragmentSource;
		if (vertexSource != null) __glVertexSourceRaw = vertexSource;

		__setDirty();
	}

	/**
	 * Constructs a GLSL shader from an asset shader file.
	 * The benefit is to be properly cached.
	 * @param fragmentPath The file fragment shader path.
	 * @param vertexPath Optional, will use fragmentPath if empty; The file vertex shader path.
	 * @param version Optional, gets from the shader file if available; The shader glsl version.
	 */
	public static function fromFile(fragmentPath:String, ?vertexPath:String, ?version:String):FlxRuntimeShader
	{
		final shader = new FlxRuntimeShader();

		if (vertexPath == null)
		{
			final idx = fragmentPath.lastIndexOf(".");
			if (idx == -1) vertexPath = fragmentPath;
			else vertexPath = fragmentPath.substr(0, idx);
		}

		shader._fromFile(_getPath(fragmentPath, false), _getPath(vertexPath, true), version);

		return shader;
	}

	/**
	 * Modify a float parameter of the shader.
	 *
	 * @param name The name of the parameter to modify.
	 * @param value The new value to use.
	 */
	public function setFloat(name:String, value:Float):Void
	{
		var prop:ShaderParameter<Float> = Reflect.field(this.data, name);
		@:privateAccess
		if (prop == null)
		{
			trace('[WARN] Shader float property ${name} not found.');
			return;
		}
		prop.value = [value];
	}

	/**
	 * Modify a float array parameter of the shader.
	 *
	 * @param name The name of the parameter to modify.
	 * @param value The new value to use.
	 */
	public function setFloatArray(name:String, value:Array<Float>):Void
	{
		var prop:ShaderParameter<Float> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader float[] property ${name} not found.');
			return;
		}
		prop.value = value;
	}

	/**
	 * Modify an integer parameter of the shader.
	 *
	 * @param name The name of the parameter to modify.
	 * @param value The new value to use.
	 */
	public function setInt(name:String, value:Int):Void
	{
		var prop:ShaderParameter<Int> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader int property ${name} not found.');
			return;
		}
		prop.value = [value];
	}

	/**
	 * Modify an integer array parameter of the shader.
	 *
	 * @param name The name of the parameter to modify.
	 * @param value The new value to use.
	 */
	public function setIntArray(name:String, value:Array<Int>):Void
	{
		var prop:ShaderParameter<Int> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader int[] property ${name} not found.');
			return;
		}
		prop.value = value;
	}

	/**
	 * Modify a boolean parameter of the shader.
	 * @param name The name of the parameter to modify.
	 * @param value The new value to use.
	 */
	public function setBool(name:String, value:Bool):Void
	{
		var prop:ShaderParameter<Bool> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader bool property ${name} not found.');
			return;
		}
		prop.value = [value];
	}

	/**
	 * Modify a boolean array parameter of the shader.
	 * @param name The name of the parameter to modify.
	 * @param value The new value to use.
	 */
	public function setBoolArray(name:String, value:Array<Bool>):Void
	{
		var prop:ShaderParameter<Bool> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader bool[] property ${name} not found.');
			return;
		}
		prop.value = value;
	}

	/**
	 * Modify a bitmap data parameter of the shader.
	 * @param name The name of the parameter to modify.
	 * @param value The new value to use.
	 */
	public function setBitmapData(name:String, value:openfl.display.BitmapData):Void
	{
		var prop:ShaderInput<openfl.display.BitmapData> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader sampler2D property ${name} not found.');
			return;
		}
		prop.input = value;
	}

	/**
	 * Retrieve a float parameter of the shader.
	 * @param name The name of the parameter to retrieve.
	 * @return The value of the parameter.
	 */
	public function getFloat(name:String):Null<Float>
	{
		var prop:ShaderParameter<Float> = Reflect.field(this.data, name);
		if (prop == null || prop.value.length == 0)
		{
			trace('[WARN] Shader float property ${name} not found.');
			return null;
		}
		return prop.value[0];
	}

	/**
	 * Retrieve a float array parameter of the shader.
	 * @param name The name of the parameter to retrieve.
	 * @return The value of the parameter.
	 */
	public function getFloatArray(name:String):Null<Array<Float>>
	{
		var prop:ShaderParameter<Float> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader float[] property ${name} not found.');
			return null;
		}
		return prop.value;
	}

	/**
	 * Retrieve an integer parameter of the shader.
	 * @param name The name of the parameter to retrieve.
	 * @return The value of the parameter.
	 */
	public function getInt(name:String):Null<Int>
	{
		var prop:ShaderParameter<Int> = Reflect.field(this.data, name);
		if (prop == null || prop.value.length == 0)
		{
			trace('[WARN] Shader int property ${name} not found.');
			return null;
		}
		return prop.value[0];
	}

	/**
	 * Retrieve an integer array parameter of the shader.
	 * @param name The name of the parameter to retrieve.
	 * @return The value of the parameter.
	 */
	public function getIntArray(name:String):Null<Array<Int>>
	{
		var prop:ShaderParameter<Int> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader int[] property ${name} not found.');
			return null;
		}
		return prop.value;
	}

	/**
	 * Retrieve a boolean parameter of the shader.
	 * @param name The name of the parameter to retrieve.
	 * @return The value of the parameter.
	 */
	public function getBool(name:String):Null<Bool>
	{
		var prop:ShaderParameter<Bool> = Reflect.field(this.data, name);
		if (prop == null || prop.value.length == 0)
		{
			trace('[WARN] Shader bool property ${name} not found.');
			return null;
		}
		return prop.value[0];
	}

	/**
	 * Retrieve a boolean array parameter of the shader.
	 * @param name The name of the parameter to retrieve.
	 * @return The value of the parameter.
	 */
	public function getBoolArray(name:String):Null<Array<Bool>>
	{
		var prop:ShaderParameter<Bool> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader bool[] property ${name} not found.');
			return null;
		}
		return prop.value;
	}

	/**
	 * Retrieve a bitmap data parameter of the shader.
	 * @param name The name of the parameter to retrieve.
	 * @return The value of the parameter.
	 */
	public function getBitmapData(name:String):Null<openfl.display.BitmapData>
	{
		var prop:ShaderInput<openfl.display.BitmapData> = Reflect.field(this.data, name);
		if (prop == null)
		{
			trace('[WARN] Shader sampler2D property ${name} not found.');
			return null;
		}
		return prop.input;
	}

	private static function _getPath(path:String, isVertex:Bool):Null<String>
	{
		final idx = path.lastIndexOf(".");
		var ext:Null<String> = null;
		if (idx != -1)
		{
			if (FlxG.assets.exists(path)) return path;
			ext = path.substr(idx + 1);
			path = path.substr(0, idx);
		}

		if (ext == null || (isVertex ? ext != "vert" : ext != "frag"))
		{
			ext = isVertex ? ".vert" : ".frag";
			if (FlxG.assets.exists(path + ext)) return path + ext;
		}

		if (!isVertex && FlxG.assets.exists(path + ".glsl")) return path + ".glsl";
		else return null;
	}

	private function _fromFile(fragmentPath:Null<String>, vertexPath:Null<String>, version:Null<String>):Void
	{
		_fragmentFilePath = fragmentPath;
		_vertexFilePath = vertexPath;

		__glVersionRaw = version;
		__glSourceDirty = true;

		if (fragmentPath == null && vertexPath == null)
		{
			__cacheProgramId = _cacheProgramIdDefault;
			__glFragmentSourceRaw = _glFragmentSourceDefault;
			__glVertexSourceRaw = _glVertexSourceDefault;
		}
		else
		{
			__cacheProgramId = 'fragmentPath: ${fragmentPath}, vertexPath: ${vertexPath}, version: ${version}';
			__glFragmentSourceRaw = fragmentPath != null ? FlxG.assets.getText(fragmentPath) : _glFragmentSourceDefault;
			__glVertexSourceRaw = vertexPath != null ? FlxG.assets.getText(vertexPath) : _glVertexSourceDefault;
		}
	}

	private function _setDirtyCache():Void
	{
		__cacheProgramId = __glFragmentSourceRaw == _glFragmentSourceDefault && __glVertexSourceRaw == _glVertexSourceDefault ? _cacheProgramIdDefault : null;
		__glSourceDirty = true;
	}

	override function __createAssembler():Void
	{
		__glSourceAssembler = new FlxShaderSourceAssembler(this);
	}

	override function set_glFragmentSource(value:String):String
	{
		_fragmentFilePath = null;
		_setDirtyCache();
		return __glFragmentSourceRaw = value ?? _glFragmentSourceDefault;
	}

	override function set_glVertexSource(value:String):String
	{
		_vertexFilePath = null;
		_setDirtyCache();
		return __glVertexSourceRaw = value ?? _glVertexSourceDefault;
	}

	override function __setDirty():Void
	{
		_fragmentFilePath = null;
		_vertexFilePath = null;
		_setDirtyCache();
	}

	public function toString():String
	{
		return __cacheProgramId != null ? 'FlxRuntimeShader(${__cacheProgramId})' : 'FlxRuntimeShader';
	}
}

class FlxShaderSourceAssembler extends GLSLSourceAssembler
{
	public final parent:FlxRuntimeShader;

	public function new(parent:FlxRuntimeShader)
	{
		super();
		this.parent = parent;
	}

	override function __getIncludeSource(include:String, fromVertex:Bool):Null<String>
	{
		if (FlxG.assets.exists(include)) return FlxG.assets.getText(include);

		@:privateAccess
		var path:Null<String> = fromVertex ? parent._vertexFilePath : parent._fragmentFilePath;
		if (path != null)
		{
			path += '/' + (StringTools.startsWith(include, './') ? include.substr(2) : include);
			if (FlxG.assets.exists(path)) return FlxG.assets.getText(path);
		}

		return super.__getIncludeSource(include, fromVertex);
	}
}