package worker.proxy {
import domain.vo.DownloadFileDescriptor;

import flash.events.ErrorEvent;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.ProgressEvent;
import flash.system.MessageChannel;
import flash.system.Worker;
import flash.system.WorkerDomain;
import flash.system.WorkerState;

import infrastructure.worker.api.downloadFileWorker.AbstractDownloadFileWorker;
import infrastructure.worker.api.downloadFileWorker.IDownloadFileWorker;

[Bindable]
public class DownloadFileWorkerProxy extends EventDispatcher implements IDownloadFileWorker {

    public static var dbPath:String;

    private var _worker:Worker;
    private var _statusChannel:MessageChannel;
    private var _commandChannel:MessageChannel;
    private var _progressChannel:MessageChannel;
    private var _errorChannel:MessageChannel;
    private var _resultChannel:MessageChannel;

    private var _workerName:String;

    private var _onProgress:Function;
    private var _onError:Function;
    private var _onCompleted:Function;

    private var _useCache:Boolean = true;

    private var _downloadFileDescriptor:DownloadFileDescriptor;

    private var _isResumable:Boolean;
    private var _isPaused:Boolean;
    private var _isRunning:Boolean;

    public function DownloadFileWorkerProxy(workerName:String, downloadFileDescriptor:DownloadFileDescriptor, onProgress:Function = null, onError:Function = null, onCompleted:Function = null):void {

        _workerName = workerName;
        _downloadFileDescriptor = downloadFileDescriptor;
        _onProgress = onProgress;
        _onError = onError;
        _onCompleted = onCompleted;

        createWorker();
    }

    private function onStateChangedWrapper(event:Event):void {

        switch (_worker.state) {
            case WorkerState.RUNNING:
            {
                isRunning = true;
                addEventListeners();

                _commandChannel.send([AbstractDownloadFileWorker.DOWNLOAD_MESSAGE, _downloadFileDescriptor]);

                break;
            }

            case WorkerState.TERMINATED:
            {
                isRunning = false;
                removeListeners();

                break;
            }
        }
    }

    private function onStatusWrapper(event:Event):void {
        var status:String = _statusChannel.receive();

        switch (status) {
            case AbstractDownloadFileWorker.RESUMABLE_STATUS:
            {
                isResumable = true;
                break;
            }
        }
    }

    private function onProgressWrapper(event:Event):void {
        _downloadFileDescriptor = _progressChannel.receive();
        var destEvent:ProgressEvent = new ProgressEvent(ProgressEvent.PROGRESS, false, false, _downloadFileDescriptor.bytesLoaded, _downloadFileDescriptor.bytesTotal);
        dispatchEvent(destEvent);
    }

    private function onErrorWrapper(event:Event):void {
        var error:Error = _errorChannel.receive();
        var destEvent:ErrorEvent = new ErrorEvent(ErrorEvent.ERROR, false, false, error.message, error.errorID);
        dispatchEvent(destEvent);
    }

    private function onCompletedWrapper(event:Event):void {
        _downloadFileDescriptor = _resultChannel.receive();
        var destEvent:Event = new Event(Event.COMPLETE);
        dispatchEvent(destEvent);
    }

    public function start():void {
        if (_worker.state == WorkerState.NEW) {
            _worker.start();
        }
    }

    public function terminate():Boolean {

        if (_worker.state == WorkerState.RUNNING) {
            _commandChannel.send(AbstractDownloadFileWorker.ABORT_MESSAGE, 0);
        }

        return _worker.terminate();
    }

    public function pause():void {
        if (_isRunning) {
            _commandChannel.send(AbstractDownloadFileWorker.PAUSE_MESSAGE);
            isPaused = true;
        }
    }

    public function resume():void {
        if (isPaused) {
            _commandChannel.send(AbstractDownloadFileWorker.RESUME_MESSAGE);
            isPaused = false;
        }
    }

    public function get useCache():Boolean {
        return _useCache;
    }

    public function set useCache(v:Boolean):void {
        _commandChannel.send(AbstractDownloadFileWorker.USE_CACHE_MESSAGE);
        _commandChannel.send(v);
        _useCache = v;
    }

    public function get isResumable():Boolean {
        return _isRunning && _isResumable;
    }

    public function set isResumable(v:Boolean):void {
        _isResumable = v;
    }

    public function get isPaused():Boolean {
        return isResumable && _isPaused;
    }

    public function set isPaused(v:Boolean):void {
        _isPaused = v;
    }

    public function get isRunning():Boolean {
        return _isRunning;
    }

    public function set isRunning(v:Boolean):void {
        _isRunning = v;
    }


    public function get fileDescriptor():DownloadFileDescriptor {
        return _downloadFileDescriptor;
    }

    public function get workerName():String {
        return _workerName;
    }

    private function createWorker():void {

        // Create the background infrastructure.worker
        _worker = WorkerDomain.current.createWorker(Workers.worker_DownloadFileWorker, true);

        _worker.setSharedProperty("workerName", _workerName);
        _worker.setSharedProperty("dbPath", dbPath);

        // Set up the MessageChannels for communication between workers
        _commandChannel = Worker.current.createMessageChannel(_worker);
        _worker.setSharedProperty(_workerName + "_commandChannel", _commandChannel);

        // Set up listeners
        _worker.addEventListener(Event.WORKER_STATE, onStateChangedWrapper);

        _statusChannel = _worker.createMessageChannel(Worker.current);
        _statusChannel.addEventListener(Event.CHANNEL_MESSAGE, onStatusWrapper);
        _worker.setSharedProperty(_workerName + "_statusChannel", _statusChannel);

        _progressChannel = _worker.createMessageChannel(Worker.current);
        _progressChannel.addEventListener(Event.CHANNEL_MESSAGE, onProgressWrapper);
        _worker.setSharedProperty(_workerName + "_progressChannel", _progressChannel);

        _errorChannel = _worker.createMessageChannel(Worker.current);
        _errorChannel.addEventListener(Event.CHANNEL_MESSAGE, onErrorWrapper);
        _worker.setSharedProperty(_workerName + "_errorChannel", _errorChannel);

        _resultChannel = _worker.createMessageChannel(Worker.current);
        _resultChannel.addEventListener(Event.CHANNEL_MESSAGE, onCompletedWrapper);
        _worker.setSharedProperty(_workerName + "_resultChannel", _resultChannel);
    }

    private function addEventListeners():void {

        if (_onProgress != null)
            addEventListener(ProgressEvent.PROGRESS, _onProgress);

        if (_onError != null)
            addEventListener(ErrorEvent.ERROR, _onError);

        if (_onCompleted != null)
            addEventListener(Event.COMPLETE, _onCompleted);
    }

    private function removeListeners():void {

        _worker.removeEventListener(Event.WORKER_STATE, onStateChangedWrapper);
        _progressChannel.removeEventListener(Event.CHANNEL_MESSAGE, onProgressWrapper);
        _errorChannel.removeEventListener(Event.CHANNEL_MESSAGE, onErrorWrapper);
        _resultChannel.removeEventListener(Event.CHANNEL_MESSAGE, onCompletedWrapper);

        if (_onProgress != null)
            removeEventListener(ProgressEvent.PROGRESS, _onProgress);

        if (_onError != null)
            removeEventListener(ErrorEvent.ERROR, _onError);

        if (_onCompleted != null)
            removeEventListener(Event.COMPLETE, _onCompleted);

        _onProgress =
                _onError =
                        _onCompleted = null;
    }
}
}