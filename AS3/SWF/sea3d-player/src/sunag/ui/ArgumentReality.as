/* Copyright (C) 2012 Sunag Entertainment
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>. */

package sunag.ui
{
	import flash.display.BitmapData;
	import flash.display.Stage;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.geom.Matrix;
	import flash.media.Camera;
	import flash.media.Video;
	import flash.system.ApplicationDomain;
	import flash.system.System;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	
	import ru.inspirit.asfeat.ASFEAT;
	import ru.inspirit.asfeat.IASFEAT;
	import ru.inspirit.asfeat.calibration.IntrinsicParameters;
	import ru.inspirit.asfeat.event.ASFEATCalibrationEvent;
	import ru.inspirit.asfeat.event.ASFEATDetectionEvent;
	import ru.inspirit.asfeat.event.ASFEATLSHIndexEvent;

	public class ArgumentReality extends EventDispatcher
	{
		public var camera:Camera;
		public var cameraBitmapData:BitmapData;
		public var invertCameraBitmapData:BitmapData;
		public var cameraVideo:Video;
		public var asfeat:ASFEAT;
		public var asfeatLib:IASFEAT;
		public var intrinsic:IntrinsicParameters;
		
		public var ram:ByteArray;
		public var width:int = 600;
		public var height:int = 400;
		public var size:int = 512;
		
		public var stage:Stage;
		public var references:Vector.<ByteArray> = null;
		
		protected static var _current:ArgumentReality;
		
		public function ArgumentReality(stage:Stage)
		{
			this.stage = stage;
		}
		
		public function init():void
		{			
			if (_current)
				throw new Error("Already has an ArgumentReality running.");
			
			if (!references || references.length == 0)
				throw new Error("No reference found.");
			
			_current = this;
			
			camera = Camera.getCamera();			
			
			if (!camera)
			{
				throw new Error("Camera is not supported.");
				return;
			}
			
			camera.setMode(width, height, 60, true);
			cameraBitmapData = new BitmapData(size, size, false, 0);
			invertCameraBitmapData = cameraBitmapData.clone(); 
			
			cameraVideo = new Video(size, size);
			
			cameraVideo.attachCamera(camera);
			
			asfeat = new ASFEAT(null);
			asfeat.addEventListener(Event.INIT, onAsfeatInit);						
		}
		
		public function dispose():void
		{
			_current = null;			
			
			asfeat.destroy();
			cameraBitmapData.dispose();
			invertCameraBitmapData.dispose();
			
			System.gc();
		}
		
		protected function onAsfeatInit(e:Event):void
		{
			asfeat.removeEventListener(Event.INIT, onAsfeatInit);
			
			asfeatLib = asfeat.lib;			
			
			var maxPointsToDetect:int = 300; // max point to allow on the screen
			var maxReferenceObjects:int = 1; // max reference objects to be used			
			var maxTransformError:Number = 10 * 10; // max transfromation error to accept
			
			// just believe me
			var ram:ByteArray = new ByteArray();
			ram.endian = Endian.LITTLE_ENDIAN;
			ram.length = asfeat.lib.calcRequiredChunkSize(size, size, maxPointsToDetect, maxReferenceObjects);
			ram.position = 0;			
			ApplicationDomain.currentDomain.domainMemory = ram;
			
			// init our engine
			asfeatLib.init(ram, 0, size, size, maxPointsToDetect, maxReferenceObjects, maxTransformError, stage);
			
			// add reference object
			for each(var data:ByteArray in references)
			{
				asfeatLib.addReferenceObject( data );			
			}			
			
			// add event listeners
			asfeatLib.addListener(ASFEATDetectionEvent.DETECTED, onModelDetected);
			asfeatLib.addListener(ASFEATCalibrationEvent.COMPLETE, onCalibDone);
			asfeatLib.addListener(ASFEATLSHIndexEvent.COMPLETE, onIndexComplete);
			
			// ATTENTION 
			// use it if u want only one model to be detected
			// and available at single frame (better performance)
			asfeatLib.setSingleReferenceMode(true);
			
			// indexing reference data will result in huge
			// speed up during matching (see docs for more info)
			asfeatLib.indexReferenceData(20, 12);
			
			// u can repform geometric calibration
			// during detection/tracking (see onCalibDone method)
			asfeatLib.startGeometricCalibration();
			
			intrinsic = asfeatLib.getIntrinsicParams();
		}
		
		protected function onModelDetected(e:ASFEATDetectionEvent):void
		{
			//trace(e.toString());
		}
		
		protected function onCalibDone(e:ASFEATCalibrationEvent):void
		{
			var fx:Number = (e.fx + e.fy) * 0.5;
			var fy:Number = fx;
			
			intrinsic.update(fx, fy, intrinsic.cx, intrinsic.cy);
			
			asfeatLib.updateIntrinsicParams();
			
			//trace( '\ncalib fx/fy: ' + [intrinsic.fx, intrinsic.fy] );
		}
		
		protected function onIndexComplete(e:ASFEATLSHIndexEvent):void 
		{
			//trace(e.indexInfo);
		}
		
		public function update():void
		{
			cameraBitmapData.draw(cameraVideo);
			invertCameraBitmapData.draw(cameraBitmapData, new Matrix(-1, 0, 0, 1, cameraBitmapData.width));							
			
			if (asfeatLib)
				asfeatLib.detect(cameraBitmapData);
		}
		
		public function get bitmapData():BitmapData
		{
			return cameraBitmapData;
		}
		
		public static function get current():ArgumentReality
		{
			return _current;
		}
	}
}