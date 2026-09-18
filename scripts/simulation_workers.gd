extends RefCounted

# The caller participates: three workers + the main thread, at most four.
# Engine-owned audio/render/driver threads are outside this simulation budget.
const MAX_WORKERS := 3
var worker_limit := MAX_WORKERS
var last_parallel_jobs := 0
var _workers: Array = []
var _start_failed := false

class Worker:
	extends RefCounted
	var thread := Thread.new()
	var wake := Semaphore.new()
	var done := Semaphore.new()
	var guard := Mutex.new()
	var stopping := false
	var job: Callable
	var first := 0
	var last := 0
	var result: Array = []
	var execution_thread := 0

	func run() -> void:
		while true:
			wake.wait()
			guard.lock()
			var stop := stopping
			var task := job
			var begin := first
			var end := last
			guard.unlock()
			if stop: return
			var output: Array = task.call(begin, end)
			guard.lock()
			result = output
			execution_thread = OS.get_thread_caller_id()
			job = Callable()
			guard.unlock()
			done.post()

	func submit(task: Callable, begin: int, end: int) -> void:
		guard.lock()
		job = task
		first = begin
		last = end
		guard.unlock()
		wake.post()

	func collect() -> Array:
		done.wait()
		guard.lock()
		var output := result
		result = []
		guard.unlock()
		return output

	func close() -> void:
		guard.lock()
		stopping = true
		guard.unlock()
		wake.post()
		thread.wait_to_finish()


# Main-thread entry only. The callable must own/read numerical snapshots only;
# no Node, scene tree, renderer, resource mutation, or random draws in workers.
func map_chunks(count: int, calculation: Callable) -> Array:
	last_parallel_jobs = 0
	# Single-threaded Web exports use the same calculation without spawning workers.
	if not OS.has_feature("threads"):
		return calculation.call(0, count)
	var wanted := mini(clampi(worker_limit, 0, MAX_WORKERS), mini(maxi(0, OS.get_processor_count() - 1), maxi(0, count - 1)))
	while _workers.size() < wanted and not _start_failed:
		var worker := Worker.new()
		if worker.thread.start(worker.run) != OK:
			_start_failed = true
			break
		_workers.append(worker)
	var active := mini(wanted, _workers.size())
	var chunks := active + 1
	for index in active:
		_workers[index].submit(calculation, count * index / chunks, count * (index + 1) / chunks)
	var tail: Array = calculation.call(count * active / chunks, count)
	var output: Array = []
	for index in active:
		output.append_array(_workers[index].collect())
	output.append_array(tail)
	last_parallel_jobs = active
	return output


func worker_count() -> int:
	return _workers.size()


func shutdown() -> void:
	for worker in _workers: worker.close()
	_workers.clear()
	last_parallel_jobs = 0
