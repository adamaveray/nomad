#!/usr/bin/php
<?php
define('VAGRANTS_PATH', $_SERVER['HOME'].'/.vagrants.json');

class Nomad {
	const STATUS_ERROR	= 1;

	/** @var string */
	protected $script;
	/** @var array */
	protected $args;
	/** @var int */
	protected $status;

	/** @var array */
	protected $directories;

	public function __construct($script, $args){
		$this->script	= $script;
		$this->args		= $args;
	}
	
	protected function printout($line){
		echo $line.PHP_EOL;
		flush();
	}

	public function run(){
		$args	= $this->args;
		if(!$args){
			$this->outputHelp();
			return;
		} else if(in_array('-h', $args) || in_array('--help', $args)){
			$this->outputHelp(current($args));
			return;
		}

		$action	= array_shift($args);
		switch($action){
			case 'add':
			case 'remove':
			case 'info':
			case 'list':
				$this->{'action'.$action}($args);
				break;

			default:
				if($action[0] === '-'){
					return $this->error();
				}

				// Assume vagrant command - pass through
				$name	= $action;
				$this->vagrantCommand($name, $args);
				break;
		}
	}


	protected function actionAdd(array $params){
		if(!isset($params[0])){
			throw new \OutOfBoundsException('No name given');
		}
		if(!isset($params[1])){
			throw new \OutOfBoundsException('No directory given');
		}
		$name		= $params[0];
		$directory	= rtrim($params[1], '/');

		if(!in_array($directory[0], ['/', '~'])){
			// Relative path
			if(strpos($directory, './') === 0){
				$directory	= substr($directory, strlen('./'));
			}

			$directory	= realpath(getcwd().'/'.$directory);
		}

		if(!is_dir($directory)){
			throw new \RuntimeException('Directory not found');

		} else if(!file_exists($directory.'/vagrantfile')){
			throw new \RuntimeException('Directory does not contain vagrant installation');
		}

		$this->addDirectory($name, $directory);
	}

	protected function actionRemove(array $params){
		if(!isset($params[0])){
			throw new \OutOfBoundsException('No name given');
		}
		$name	= $params[0];

		$this->removeDirectory($name);
	}

	protected function actionInfo(array $params){
		if(!isset($params[0])){
			throw new \OutOfBoundsException('No name given');
		}
		$name	= $params[0];
		
		$directory	= $this->getDirectory($name);
		$this->printout($directory);
	}

	protected function actionList(){
		$directories	= $this->getDirectories();

		if(!$directories){
			echo '(No Vagrants added)'.PHP_EOL;
			return;
		}

		echo implode(PHP_EOL, array_keys($directories)).PHP_EOL;
	}

	protected function vagrantCommand($name, $args){
		$directory	= $this->getDirectory($name);

		if(!isset($args[0])){
			throw new \OutOfBoundsException('No Vagrant command given');
		}
		$command	= array_shift($args);

		$this->executeCommand($directory, 'vagrant '.$command, $args);
	}


	public function outputHelp($action = null){
		if(!isset($action) || in_array($action, ['-h', '--help'])){
			$output	= <<<TXT
Usage: {$this->script} [-h] command [name] [<args>]

    -h, --help                       Print this help.

Available subcommands:
    add
    remove
    info
    list
    <any Vagrant command>
TXT;
			$this->printout($output);
			return;
		}

		switch($action){
			case 'add':
				$help = <<<TXT
Usage: {$this->script} add name directory [-h]

Adds the Vagrant VM in [directory] to Nomad under the name [name]. [directory] can be relative
to the current working directory.

    -h, --help                       Print this help
TXT;

				break;

			case 'remove':
				$help = <<<TXT
Usage: {$this->script} remove name [-h]

Removes the Vagrant VM [name] from Nomad

	-h, --help                       Print this help
TXT;
				break;

			case 'info':
				$help = <<<TXT
Usage: {$this->script} info name [-h]

Shows the directory for the Vagrant VM [name]

    -h, --help                       Print this help
TXT;
				break;

			case 'list':
				$help = <<<TXT
Usage: {$this->script} list [-h]

Outputs all the available Vagrant VMs

    -h, --help                       Print this help
TXT;
				break;

			default:
				throw new \OutOfRangeException('Unknown action "'.$action.'"');
				break;
		}

		$this->printout($help);
	}

	protected function executeCommand($directory, $command, array $args = null){
		$args	= (array)$args;
		foreach($args as &$arg){
			$arg	= escapeshellarg($arg);
		}

		$descriptorspec = [
			0	=> ['pipe', 'r'],	// stdin - read
			1	=> ['pipe', 'w'],   // stdout - write
			2	=> ['pipe', 'w']    // stderr - write
		];

		flush();
		$process = proc_open('cd "'.$directory.'"; '.$command.' '.implode(' ', $args), $descriptorspec, $pipes, realpath('./'));

		if(!is_resource($process)){
			return;
		}
		while($s = fgets($pipes[1])){
			print $s;
			flush();
		}
	}


	protected function getDirectory($name){
		$directories	= $this->getDirectories();
		if(!isset($directories[$name])){
			throw new \OutOfRangeException('Name does not exist');
		}

		return $directories[$name];
	}

	protected function getDirectories(){
		if(!isset($this->directories)){
			if(!file_exists(VAGRANTS_PATH)){
				// Create empty vagrants file
				$this->saveDirectories([]);
			}

			$this->directories	= json_decode(file_get_contents(VAGRANTS_PATH), true);

			if(!isset($this->directories)){
				throw new \RuntimeException('Could not load directories');
			}
		}

		return $this->directories;
	}

	protected function addDirectory($name, $directory){
		$directories	= $this->getDirectories();
		$directories[$name]	= $directory;
		$this->saveDirectories($directories);
	}

	protected function removeDirectory($name){
		$directories	= $this->getDirectories();
		unset($directories[$name]);
		$this->saveDirectories($directories);
	}

	protected function saveDirectories($directories){
		if(file_exists(VAGRANTS_PATH)){
			// Already exists - test if editable
			if(!is_writeable(VAGRANTS_PATH)){
				throw new \RuntimeException('Cannot write to vagrants file');
			}

		} else {
			// Does not exist - test if createable
			if(!is_writeable(dirname(VAGRANTS_PATH))){
				throw new \RuntimeException('Cannot create vagrants file');
			}
		}

		file_put_contents(VAGRANTS_PATH, json_encode($directories, \JSON_PRETTY_PRINT));
	}

	public function getStatus(){
		return $this->status;
	}


	protected function error(){
		$this->status	= static::STATUS_ERROR;
	}
};


// Run Nomad
$args	= $argv;
try {
	$nomad	= new Nomad(array_shift($args), $args);
	$nomad->run();
	return $nomad->getStatus();

} catch(Exception $e){
	echo 'Error: '.$e->getMessage().PHP_EOL;
	return Nomad::STATUS_ERROR;
}
