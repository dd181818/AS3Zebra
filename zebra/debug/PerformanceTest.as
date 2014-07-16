package zebra.debug
{
	import flash.utils.describeType
	import flash.utils.getTimer;
	import flash.events.Event;
	import flash.display.Shape;
	import flash.net.LocalConnection;
	import flash.display.DisplayObject;
	import flash.geom.Rectangle;
	import flash.geom.Matrix;
	import flash.display.Shape;
	import flash.display.BitmapData;
	import flash.system.Capabilities;
	
	/**
	 * This class represents a first attempt at creating a simple, but powerful performance testing harness for
	 * ActionScript 3. Its most important feature is testing and reporting on simple to write test suite classes.
	 * This is useful both for testing language features (ex. which loop structure runs fastest, what are the
	 * performance advantages of Vectors over Arrays), and for creating frameworks for testing the performance of
	 * projects as they are developed.<br/>
	 * <br/>
	 * PerformanceTest instances maintain a queue, and will run multiple tests in order. Each method that is tested
	 * will be run asynchronously (iterations of the method test are run synchronously) unless .synchronous is set to
	 * true. The garbage collector is run in between each method test to provide better isolated results.
	 * <br/>
	 * Note that it is generally good practice to wait a few seconds after your SWF loads to run performance tests.
	 * This ensures that the Flash player's start up and loading operations don't interfere with the test results.
	 **/
	public class PerformanceTest
	{
		
		// Static interface:
		/** @private **/
		protected static var _instance:PerformanceTest;
		
		/**
		 * This is a convenience function to allow you to access a single instance of PerformanceTest globally, so that
		 * you have a single test queue.
		 **/
		public static function getInstance():PerformanceTest
		{
			return _instance ? _instance : _instance = new PerformanceTest();
		}
		
		// Public Properties:
		/**
		 * Specifies a function to handle the text output from the default logging. You could use this
		 * to write the default output to a file, or display it in a text field. For example
		 * setting <code>myPerformanceTest.out = trace;</code> will cause the log output to be traced.
		 **/
		public var out:Function;
		
		/**
		 * Specifies an object to handle logging results as they are generated. This allows you to bypass the
		 * default text logging output, in order to store, chart or display the output differently. The logger object
		 * must expose 4 methods:<br/>
		 * <br/>
		 * <code>logBegin(name:String,description:String,iterations:uint)</code><br/>
		 * Called when a new test begins.<br/>
		 * <br/>
		 * <code>logError(name:String,details:Error)</code><br/>
		 * Called if an error occurs while testing a method. The details parameter will be null if the
		 * method was not found in the test suite, or will error object that was generated if an error
		 * occured while running the method.<br/>
		 * <br/>
		 * <code>logMethod(name:String, time:uint, iterations:uint, details:*)</code><br/>
		 * Called after a method was tested successfully. The time parameter will be passed the total
		 * time for all iterations, calculate average with <code>time/iterations</code>. Currently, the
		 * the details parameter is only passed a value for "tare" methods - the number of times the tare
		 * method was run before returning consistent timing.<br/>
		 * <br/>
		 * <code>logEnd(name:String)</code>
		 * Called when a test ends.
		 */
		public var logger:Object;
		
		/*
		 * When synchronous is set to false (default) each method is tested in a separate frame to prevent
		 * the tests from freezing the UI or timing out. Setting synchronous to true forces tests to run
		 * immediately when added, and all within the same frame.
		 */
		public var synchronous:Boolean = false;
		
		// Protected Properties:
		/** @private **/
		protected var queue:Array;
		/** @private **/
		protected var _queue:Array;
		/** @private **/
		protected var div:String;
		/** @private **/
		protected var _paused:Boolean = false;
		/** @private **/
		protected var _synchronousTestResults:Number;
		/** @private **/
		protected var _synchronous:Boolean;
		/** @private **/
		protected var shape:Shape;
		
		// Initialization:
		public function PerformanceTest()
		{
			init();
		}
		
		// Public getter / setters:
		/**
		 * Pauses or resumes the performance test queue.
		 **/
		public function get paused():Boolean
		{
			return _paused;
		}
		
		public function set paused(value:Boolean):void
		{
			_paused = value;
			if (value)
			{
				stopTick();
			}
			else if (queue.length > 0)
			{
				startTick();
			}
		}
		
		// Public Methods:
		/**
		 * Allows you to test the performance of a single function. Handy for testing functions on the timeline.
		 * @param testFunction The function to test.
		 * @param iterations The number of times to run the function. More iterations will take longer to run, but will result in a more consistent result.
		 * @param name The name to use when logging this test.
		 * @param description The description to use when logging this test.
		 **/
		public function testFunction(testFunction:Function, iterations:uint = 1, name:String = "Function", description:String = null):void
		{
			var o:Object = {testSuite: testFunction, iterations: iterations, name: name, description: description, index: 0, tare: 0, tareCount: -1};
			o.methods = [name];
			addTest(o);
		}
		
		/**
		 * This method allows you to test the time it takes to render a complex display object. This is a largely untested feature in this version of PerformanceSuite.
		 * @param displayObject A DisplayObject to test rendering times for. For example you could test the render time of a display object with complex vectors or filters.
		 * @param bounds Specifies the area of the display object to render. For example, you might want to limit the render to the area that would be visible on the stage at runtime. If bounds is not specified, it will use the bounds of the display object.
		 * @param iterations The number of times to run the render. More iterations will take longer to run, but will result in a more consistent result.
		 * @param name The name to use when logging this test.
		 * @param description The description to use when logging this test.
		 **/
		public function testRender(displayObject:DisplayObject, bounds:Rectangle = null, iterations:uint = 1, name:String = "Render", description:String = null):void
		{
			var o:Object = {testSuite: displayObject, iterations: iterations, name: name, description: description, index: 0, tare: 0, tareCount: -1};
			o.methods = ["tare", "[render]"];
			
			// if bounds weren't specified then calculate them:
			if (bounds == null)
			{
				bounds = displayObject.getBounds(displayObject);
			}
			o.bounds = bounds;
			
			// check to ensure that we can create a large enough BitmapData object:
			try
			{
				o.bitmapData = new BitmapData(bounds.width, bounds.height, true, 0);
			}
			catch (e:*)
			{
				throw(new Error("Specified bounds or displayObject dimensions are too large to render."));
			}
			
			addTest(o);
		}
		
		/**
		 * Tests a suite of methods. The suite can be any class instance with public methods. The suite object can optionally
		 * expose <code>name</code>, <code>description</code>, and <code>methods</code> properties that will be used if the
		 * corresponding parameters are not specified. The suite can also expose a <code>tare</code> method (see below for info).<br/>
		 * <br/>
		 * A test suite should group similar tests together (ex. testing different loop structures), and each test method should
		 * run for a significant amount of time (because testing methods that run for only a few ms is unreliable). You can use
		 * a loop inside of your test methods to make simple operations run longer.<br/>
		 * <br/>
		 * Similar to unit testing, you can write test suites alongside your main project files, and have the test suite methods
		 * call methods in your project to test them. In this way you can create an evolving performance testing framework
		 * without having to modify your project source code.<br/>
		 * <br/>
		 * <b>See the samples for more information on writing test suites.</b><br/>
		 * <br/>
		 * <b>Tare methods</b><br/>
		 * If a test suite exposes a public method called tare, it will be run repeatedly (up to 6 times) at the beginning of
		 * the suite until it returns a consistent timing result. That time will then be subtracted from the results of all other tests.
		 * This is useful for accounting for "infrastructure costs".<br/>
		 * <br/>
		 * For example, if you have a suite of tests to test mathematical
		 * operations, and every test has a loop to repeat the operation 100000 times (to get measureable results), you could write
		 * a tare method that contains an empty loop that repeats 100000 times, to eliminate the time required to run the loop from your results.
		 * @param testSuite The test suite instance to test.
		 * @param methods An array of method names to test. If null, the testSuite will be introspected, and all of its public methods will be tested (except those whose names begin with an underscore).
		 * @param iterations The number of times to run each method. More iterations will take longer to run, but will result in a more consistent result.
		 * @param name The name to use when logging this test.
		 * @param description The description to use when logging this test.
		 **/
		public function testSuite(testSuite:Object, methods:Array = null, iterations:uint = 0, name:String = null, description:String = null):void
		{
			
			// look up number of iterations, first in param, then as a property, then default to 1.
			if (iterations == 0 && "iterations" in testSuite)
			{
				iterations = Number(testSuite.iterations);
			}
			if (iterations == 0)
			{
				iterations = 1;
			}
			
			// just use a generic object to store test info internally.
			var o:Object = {testSuite: testSuite, iterations: iterations, name: name, description: description, index: 0, tare: 0, tareCount: -1};
			
			// get the description:
			if (description == null && "description" in testSuite)
			{
				o.description = String(testSuite.description);
			}
			
			// introspect the test suite instance:
			var desc:XML = describeType(testSuite);
			
			if (name == null && "name" in testSuite)
			{
				o.name = String(testSuite.name);
			}
			else
			{
				o.name = desc.@name.split("::").join(".");
			}
			
			// assemble the methods list:
			if (methods != null)
			{
				// use the methods param:
				o.methods = methods.slice(0);
			}
			else if ("methods" in testSuite && testSuite.methods is Array)
			{
				// use the methods property on the test suite object:
				o.methods = testSuite.methods.slice(0);
			}
			else
			{
				// no methods explicitly specified, so we will introspect the
				// test suite for public methods:
				o.methods = [];
				var methodList:XMLList = desc..method;
				for (var i:int = 0; i < methodList.length(); i++)
				{
					var methodName:String = methodList[i].@name;
					
					// ignore methods that start with underscore:
					if (methodName.charAt(0) == "_")
					{
						continue;
					}
					o.methods.push(methodName);
				}
				// sort the method list, so there's some kind of order to the report:
				o.methods.sort(Array.CASEINSENSITIVE);
			}
			
			// look for a tare method (used to establish a base time for all tests in a suite):
			if (o.methods.indexOf("tare") != -1)
			{
				o.methods.splice(o.methods.indexOf("tare"), 1);
				o.methods.unshift("tare");
				o.tareCount = 0;
			}
			
			// add the queue, and run it if there's nothing already running:
			addTest(o);
		}
		
		/**
		 * Runs a test suite in synchronous mode and returns false if the average time (accounting for number of
		 * iterations) is greater than the specified targetTime. This is useful for developing unit tests
		 * for performance. For instance, the following example would fail the unit test if mySuite took
		 * longer than 100ms to run on average per iteration:<br/>
		 * <code>assertTrue(PerformanceTest.getInstance().unitTestSuite(100, mySuite));</code>
		 **/
		public function unitTestSuite(targetTime:uint, testSuite:Object, methods:Array = null, iterations:uint = 0):Boolean
		{
			startSynchronousTest();
			this.testSuite(testSuite, methods, iterations);
			endSynchronousTest();
			return _synchronousTestResults <= targetTime;
		}
		
		/**
		 * Runs a test function in synchronous mode and returns false if the average time (accounting for number of
		 * iterations) is greater than the specified targetTime. This is useful for developing unit tests
		 * for performance. For instance, the following example would fail the unit test if myFunction took
		 * longer than 100ms to run on average per iteration:<br/>
		 * <code>assertTrue(PerformanceTest.getInstance().unitTestFunction(100, myFunction));</code><br/>
		 **/
		public function unitTestFunction(targetTime:uint, testFunction:Function, iterations:uint = 1):Boolean
		{
			startSynchronousTest();
			this.testFunction(testFunction, iterations);
			endSynchronousTest();
			return _synchronousTestResults <= targetTime;
		}
		
		/**
		 * Runs a test render in synchronous mode and returns false if the average time (accounting for number of
		 * iterations) is greater than the specified targetTime. This is useful for developing unit tests
		 * for performance. For instance, the following example would fail the unit test if mySprite took
		 * longer than 100ms to render on average per iteration:<br/>
		 * <code>assertTrue(PerformanceTest.getInstance().unitTestRender(100, mySprite));</code>
		 **/
		public function unitTestRender(targetTime:uint, displayObject:DisplayObject, bounds:Rectangle = null, iterations:uint = 1):Boolean
		{
			startSynchronousTest();
			testRender(displayObject, bounds, iterations);
			endSynchronousTest();
			return _synchronousTestResults <= targetTime;
		}
		
		// Protected Methods:
		/** @private **/
		protected function init():void
		{
			if (queue != null)
			{
				return;
			}
			queue = [];
			shape = new Shape();
			div = "";
			while (div.length < 72)
			{
				div += "–";
			}
			if (out == null)
			{
				out = trace;
			}
		}
		
		/** @private **/
		protected function addTest(o:Object):void
		{
			queue.push(o);
			if (queue.length == 1)
			{
				runNext();
			}
		}
		
		/** @private **/
		protected function runNext():void
		{
			if (queue.length < 1 || _paused)
			{
				return;
			}
			
			// log the start of this test:
			var o:Object = queue[0];
			getLogger().logBegin(o.name, o.description, o.iterations);
			
			startTick();
		}
		
		/** @private **/
		protected function startSynchronousTest():void
		{
			_synchronous = synchronous;
			_synchronousTestResults = 0;
			_queue = queue;
			queue = [];
			synchronous = true;
		}
		
		/** @private **/
		protected function endSynchronousTest():void
		{
			queue = _queue;
			synchronous = _synchronous;
			if (queue.length)
			{
				startTick();
			}
		}
		
		/** @private **/
		protected function runNextMethod():void
		{
			var o:Object = queue[0];
			if (o.index == o.methods.length)
			{
				finish();
				return;
			}
			
			var methodName:String = o.methods[o.index];
			var method:Function;
			
			// find the method to run:
			if (o.testSuite is DisplayObject)
			{
				// testing a render.
				method = methodName == "tare" ? renderTare : render;
			}
			else if (o.testSuite is Function)
			{
				// testing a single function.
				method = o.testSuite;
			}
			else if (!(methodName in o.testSuite))
			{
				// method doesn't exist, flag it, and run the next test immediately:
				getLogger().logError(methodName, null);
				o.index++;
				runNextMethod();
				return;
			}
			else
			{
				// grab the method from the test suite:
				method = o.testSuite[methodName];
			}
			
			// force the GC to run, to try to keep results more consistent:
			try
			{
				new LocalConnection().connect("_FORCE_GC_");
				new LocalConnection().connect("_FORCE_GC_");
			}
			catch (e:*)
			{
			}
			
			// run the method the number of times specified by iterations:
			var iterations:int = o.iterations;
			var t:int = getTimer();
			for (var i:int = 0; i < iterations; i++)
			{
				try
				{
					method();
				}
				catch (e:*)
				{
					o.index++;
					getLogger().logError(methodName, e);
					startTick();
					return;
				}
			}
			
			// calculate elapsed time:
			t = getTimer() - t;
			
			// if it's the tare function we treat it specially:
			if (methodName == "tare")
			{
				o.tareCount++;
				if (o.tareCount > 1)
				{
					// calculate the percent variance between the last tare and this one
					// and check if it is under 10% or 2ms different:
					if (Math.abs(o.tare - t) / t < 0.1 || Math.abs(o.tare - t) <= 2 || o.tareCount > 5)
					{
						o.index++;
						t = (t + o.tare) / 2;
						
						getLogger().logMethod(methodName, t, iterations, o.tareCount);
					}
					o.tare = t;
				}
			}
			else
			{
				// not the tare function, so subtract the tare time, and proceed to the next test:
				t -= o.tare;
				o.index++;
				
				getLogger().logMethod(methodName, t, iterations, null);
				_synchronousTestResults += t / iterations;
			}
			startTick();
		}
		
		/** @private **/
		protected function finish():void
		{
			stopTick();
			
			// log the end of this test:
			getLogger().logEnd(queue[0].name);
			
			// remove the last test from the queue:
			queue.shift();
			
			runNext();
		}
		
		/** @private **/
		protected function tick(evt:Event):void
		{
			stopTick();
			runNextMethod();
		}
		
		protected function startTick():void
		{
			if (synchronous)
			{
				tick(null);
			}
			else
			{
				shape.addEventListener(Event.ENTER_FRAME, tick);
			}
		}
		
		protected function stopTick():void
		{
			shape.removeEventListener(Event.ENTER_FRAME, tick);
		}
		
		/** @private **/
		protected function getLogger():Object
		{
			return logger ? logger : this;
		}
		
		/** @private **/
		protected function render():void
		{
			var o:Object = queue[0];
			o.bitmapData.fillRect(o.bitmapData.rect, 0);
			var mtx:Matrix = new Matrix(1, 0, 0, 1, -o.bounds.x, -o.bounds.y);
			o.bitmapData.draw(o.testSuite, mtx);
		}
		
		/** @private **/
		protected function renderTare():void
		{
			var o:Object = queue[0];
			o.bitmapData.fillRect(o.bitmapData.rect, 0);
			var mtx:Matrix = new Matrix(1, 0, 0, 1, -o.bounds.x, -o.bounds.y);
		}
		
		// default logging methods:
		/** @private **/
		protected function logBegin(name:String, description:String, iterations:uint):void
		{
			log(div);
			log(pad(name + " (" + iterations + " iterations)", 72));
			log("Player version: " + Capabilities.version + " " + (Capabilities.isDebugger ? "(debug)" : "(regular)"));
			if (description)
			{
				log(pad(description, 72));
			}
			log(div);
			log(pad("method", 54, ".") + "." + pad("ttl ms", 8, ".", true) + "." + pad("avg ms", 8, ".", true));
		}
		
		/** @private **/
		protected function logError(name:String, details:Error):void
		{
			if (details == null)
			{
				log("* " + pad((name == "" ? "" : name + " not found."), 72));
			}
			else
			{
				log("* " + name + ": " + String(details));
			}
		}
		
		/** @private **/
		protected function logMethod(name:String, time:uint, iterations:uint, details:*):void
		{
			if (details != null)
			{
				log(pad(name + " [" + String(details) + "]", 54) + " " + pad(time, 8, " ", true) + " " + pad(formatNumber(time / iterations), 8, " ", true));
			}
			else
			{
				log(pad(name, 54) + " " + pad(time, 8, " ", true) + " " + pad(formatNumber(time / iterations), 8, " ", true));
			}
		}
		
		/** @private **/
		protected function logEnd(name:String):void
		{
			log(div);
			log("");
		}
		
		/** @private **/
		protected function pad(str:*, cols:uint, char:String = " ", lpad:Boolean = false):String
		{
			str = String(str);
			if (str.length > cols)
			{
				return str.substr(0, cols);
			}
			while (str.length < cols)
			{
				str = lpad ? char + str : str + char;
			}
			return str;
		}
		
		/** @private **/
		protected function log(str:String):void
		{
			if (out != null)
			{
				out(str);
			}
		}
		
		/** @private **/
		protected function formatNumber(num:Number, decimal:uint = 2):String
		{
			var m:Number = Math.pow(10, decimal);
			var str:String = String((Math.round(num * m) + 0.5) / m);
			return str.substr(0, str.length - 1);
		}
	
	}

}

