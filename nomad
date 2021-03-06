#!/usr/bin/php
<?php
/*! Nomad 1.3.1 | github.com/adamaveray/nomad | MIT */

define('VAGRANTS_PATH', $_SERVER['HOME'].'/.vagrants.json');
define('BR', "\n");

class Nomad {
	const STATUS_ERROR	= 1;
	const UPDATE_URL	= 'https://raw.github.com/adamaveray/nomad/master/nomad';

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
	
	protected function printout($line, $linebreak = true){
		echo $line.($linebreak ? BR : '');
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
			case 'update':
			case 'restart':
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

	protected function actionRestart(array $params){
		if(!isset($params[0])){
			throw new \OutOfBoundsException('No name given');
		}
		$name	= array_shift($params);
		
		if(isset($params[0]) && $params[0][0] == '-'){
			return $this->error();
		}
		
		array_unshift($params, 'halt');
		$this->vagrantCommand($name, $params);
		
		array_shift($params);
		array_unshift($params, 'up');
		$this->vagrantCommand($name, $params);
	}

	protected function actionList(array $params){
		$directories	= $this->getDirectories();
		$getStatuses	= (in_array('-s', $params) || in_array('--status', $params));

		if(!$directories){
			$this->printout('(No Vagrants added)');
			return;
		}
		
		foreach($directories as $name => $directory){
			$output	= '';
			if($getStatuses){
				// Check status
				$boxes		= $this->getMachineStatuses($directory);
				$statuses	= [];

				if(count($boxes) === 1){
					$output	= ': '.current($boxes);

				} else if($boxes){
					foreach($boxes as $box => $status){
						$statuses[]	= $box.': '.$status;
					}

					$list	= BR.'  - ';
					$output	= $list.implode($list, $statuses);

				} else {
					$output	= '[no boxes]';
				}
			}

			$this->printout($name.$output);
		}
	}

	protected function actionUpdate(array $params){
		$newSource	= $this->getNewestScript();
		if(!isset($newSource)){
			throw new \RuntimeException('Cannot download script');
		}

		if(!$this->needsUpdate($newSource)){
			$this->printout('Already up to date');
			return;
		}

		// Update
		file_put_contents(__FILE__, $newSource);
		$this->printout(__CLASS__.' updated');
	}


	protected function getNewestScript(){
		$newSource	= file_get_contents(static::UPDATE_URL);
		if(!$newSource){
			return;
		}

		return $newSource;
	}

	protected function needsUpdate($newSource = null, $currentSource = null){
		if(!isset($newSource)){
			$newSource	= $this->getNewestScript();
			if(!isset($newSource)){
				throw new \RuntimeException('Cannot download script');
			}
		}
		if(!isset($currentSource)){
			$currentSource	= file_get_contents(__FILE__);
		}

		$current	= sha1(file_get_contents(__FILE__));
		$new		= sha1($newSource);
		return ($current !== $new);
	}

	protected function getMachineStatuses($directory){
		$response	= $this->executeCommand($directory, 'vagrant status', null, false);
		$lines	= preg_split('~\n~', $response, -1, \PREG_SPLIT_NO_EMPTY);
		
		$boxes	= [];
		
		for($i = 1, $count = count($lines); $i < $count; $i++){
			$line	= trim($lines[$i]);
			if($line === '' || !preg_match('~^(\S+)\s+([\w\s]+?)\s\((\w+)\).*?$~', $line, $matches)){
				// End of machines
				break;
			}
			
			$boxes[$matches[1]]	= $matches[2];
		}
		
		return $boxes;
	}

	protected function vagrantCommand($name, array $args, $print = null){
		$directory	= $this->getDirectory($name);

		if(!isset($args[0])){
			throw new \OutOfBoundsException('No Vagrant command given');
		}
		$command	= array_shift($args);
		
		$passthrough	= false;
		switch($command){
			case 'ssh':
				$passthrough	= true;
				break;
		}

		// Pass through command
		$this->executeCommand($directory, 'vagrant '.$command, $args, $print, $passthrough);
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
    update
    restart
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
Usage: {$this->script} info name [-s] [-h]

Shows the directory for the Vagrant VM [name]

    -h, --help                       Print this help
TXT;
				break;

			case 'list':
				$help = <<<TXT
Usage: {$this->script} list [-h]

Outputs all the available Vagrant VMs

    -s, --status                     Show each machine's status
    -h, --help                       Print this help
TXT;
				break;

			case 'restart':
				$help = <<<TXT
Usage: {$this->script} restart [-h]

Halts and ups the Vagrant VM

    -h, --help                       Print this help
TXT;
				break;

			case 'update':
				$help = <<<TXT
Usage: {$this->script} update [-h]

Updates the script to the latest version

    -h, --help                       Print this help
TXT;
				break;

			default:
				throw new \OutOfRangeException('Unknown action "'.$action.'"');
				break;
		}

		$this->printout($help);
	}

	protected function executeCommand($directory, $command, array $args = null, $print = null, $passthrough = false){
		if(!isset($print)){
			$print	= true;
		}
		
		$args	= (array)$args;
		foreach($args as &$arg){
			$arg	= escapeshellarg($arg);
		}
		
		if($passthrough){
			$output	= passthru('cd "'.$directory.'"; '.$command.' '.implode(' ', $args));
			
		} else {
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
		
			$output	= '';
			while($s = fgets($pipes[1])){
				$output	.= $s;
				if($print){
					$this->printout($s, false);
				}
			}
		
			proc_close($process);
		}
		
		return $output;
	}


	protected function getDirectory($name){
		$directories	= $this->getDirectories();
		if(!isset($directories[$name])){
			throw new \OutOfRangeException('Name "'.$name.'" does not exist');
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
	echo 'Error: '.$e->getMessage().BR;
	return Nomad::STATUS_ERROR;
}
