#!/usr/bin/env perl 
package Module::ModuleLoader;
#------------------------------------------------------------------------------
# Perl module intended for setting up the machine environment (loading modules, soft environment, etc)
# Currently specific to the module system, which as of Oct 2014 is every CESM supported machine save
# mira. 
#------------------------------------------------------------------------------
use strict;
use warnings;
use XML::LibXML;
use Data::Dumper;
use Cwd;

#------------------------------------------------------------------------------
# Constructor.  We need the machine and scriptsroot, and optionally the compiler, 
# mpi library, and whether DEBUG is on.   We also want to initialize the module system so this object
# is ready to load modules.  
#------------------------------------------------------------------------------
sub new 
{
	my ($class, %params) = @_;
	if(! defined $params{'machine'})
	{
		die "ModuleLoader requires a machine argument";
	}
	if(! defined $params{'cimeroot'})
	{
		die "ModuleLoader requires the cimeroot";
	}
	if(! defined $params{'caseroot'})
	{
		die "ModuleLoader requires the caseroot";
	}
	my $self = {	
		machine => $params{'machine'} || undef,
		compiler => $params{'compiler'} || undef,
		mpilib =>   $params{'mpilib'} || undef,
		debug  =>   $params{'debug'} || undef,
		cimeroot => $params{'cimeroot'} || undef,
		caseroot => $params{'caseroot'} || undef,
	};
	if(! defined $params{'debug'} )
	{
		$self->{debug} = 'false';
	}
	$self->{machroot} = Cwd::abs_path($self->{cimeroot}) . "/machines/";
	my $toolsroot = $self->{'caseroot'} . "/Tools";
	push(@INC, $toolsroot);
	$self->{'toolsroot'} = $toolsroot;
	#require ConfigCase;
	bless $self, $class;
	$self->moduleInit();
	return $self;
}

#------------------------------------------------------------------------------
# eval the env_mach_specific file for this machine, which should give us the new environment, 
# then insert the new or modified environment variables into %ENV
# TODO: remove!
#------------------------------------------------------------------------------
sub loadModulesCshEval()
{
	my $self = shift;
	#my $self = {	
	#	machine => $params{'machine'} || undef,
	#	compiler => $params{'compiler'} || undef,
	#	mpilib =>   $params{'mpilib'} || undef,
	#	debug  =>   $params{'debug'} || undef,
	#	scriptsroot => $params{'scriptsroot'} || undef,
	#	caseroot => $params{'caseroot'} || undef,
	#};
	#eval qx($self->{cmdpath} $cmd);

	if(defined $ENV{CIME_MODULES_LOADED}) {return $self};

	my %oldenv = %ENV;
	my $envfile = $self->{'caseroot'} . "/env_mach_specific";
	my $cshenv = "env ";
    $cshenv .= "COMPILER=". $self->{'compiler'} . " " ;
    $cshenv .= "MPILIB=". $self->{'mpilib'} . " " ;
    $cshenv .= "DEBUG=". $self->{'debug'} . " " ;
    $cshenv .= "CASEROOT=". $self->{'caseroot'} . " " ;
    $cshenv .= "PERL=TRUE ";
	#my $cmd = $cshenv . " " . $envfile;
	#my $cmd = $cshenv . " " . $envfile . " && printenv";
	my $cmd = $cshenv . " " . $envfile ;
	#print "running command $cmd\n";
	my @output;
	eval { @output = qx($cmd);};
	#eval { $out = `$cmd`;};
	#$out = `$cmd`;
	chomp @output;
	if($?)
	{
		die "could not load modules for machine $self->{'machine'}";
	}
	my %newenv;
	
	#foreach my $line(@output)
	for my $i(0 .. $#output)
	{
		chomp $output[$i];
		if($output[$i] !~ /=/)
		{
			$output[$i] = '';
		}
		if($output[$i] =~ /BASH_FUNC/i)
		{
			$output[$i] = '';
		}
	}
	foreach my $line(@output)
	{
		if(length($line) > 0)
		{
	            chomp $line;
	            #print "line: $line\n";
	            my ($key, $value) = split('=', $line, 2);
	            $newenv{$key} = $value;
                }
	}
	my %newbuildenv;
	
	foreach my $k(keys %newenv)
	{
		if(! defined $oldenv{$k})
		{
		    #print "new env var: $newenv{$k}\n";
			$newbuildenv{$k} = $newenv{$k};
			$ENV{$k} = $newenv{$k};
		}
		if(defined $oldenv{$k} && $newenv{$k} ne $oldenv{$k})
		{
		    #print "modified env var: $newenv{$k}\n";
			$newbuildenv{$k} = $newenv{$k};
			$ENV{$k} = $newenv{$k};
		}
	}
	$ENV{CIME_MODULES_LOADED} = 1;
	return %newbuildenv;

}

sub moduleInit()
{
	my $self = shift;
	my $configmachinesfile = "$self->{machroot}/config_machines.xml";
	my $machine = $self->{machine};
	if(! -e $configmachinesfile)
	{
        die "$configmachinesfile not found\n";     
	}
	else
	{
		$self->{configmachinesfile} = $configmachinesfile;
	}
    
    $self->{machspecificfile} = $self->{'caseroot'} . "/env_mach_specific.xml";
	
	# Set up the XML::LibXML parser..
	my $parser = XML::LibXML->new(no_blanks => 1);
	my $xml = $parser->parse_file($self->{'configmachinesfile'});
	$self->{configmachinesroot} = $xml;

    # First, get the module system type. 
    my @moduletypes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system");
    #my $modulesystemtype;
    foreach my $modtype(@moduletypes)
    {
        $self->{modulesystemtype} = $modtype->getAttribute('type');
    }
	
	# Get the init_path.  Module systems usually have an 'init' script for 
	# various scripting languages, we need to get this path from config_machines
    # We want to use Bourne shell for soft, there is no way to load modules via Perl 
    # for the soft environment
	my @initnodes; 
    if($self->{modulesystemtype} eq 'soft')
    {
        @initnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/init_path[\@lang=\'sh\']");
    }
	elsif($self->{modulesystemtype} eq 'dotkit')
	{
        @initnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/init_path[\@lang=\'csh\']");
	}
    elsif($self->{modulesystemtype} eq 'module')
    {
        @initnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/init_path[\@lang=\'perl\']");
    }
	foreach my $initnode(@initnodes)
	{
		$self->{initpath} = $initnode->textContent();
	}
	if(! defined $self->{initpath})
	{
		die "the module init path could not be found for the machine $machine\n";
	}

	#my @cmdnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/cmd_path");
    my @cmdnodes;
	if($self->{modulesystemtype} eq 'soft')
	{
		@cmdnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/cmd_path[\@lang=\'sh\']");
	}
	elsif($self->{modulesystemtype} eq 'dotkit')
	{
		@cmdnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/cmd_path[\@lang=\'csh\']");
	}
	elsif($self->{modulesystemtype} eq 'module')
	{
		@cmdnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/cmd_path[\@lang=\'perl\']");
	}
	foreach my $cmdnode(@cmdnodes)
	{
		$self->{cmdpath} = $cmdnode->textContent();
	}
	if(! defined $self->{cmdpath})
	{
		die "the module cmd path could not be found for the machine $machine\n";
	}
	#print "self modulesystemtype: $self->{modulesystemtype}\n";
	#print "self cmdpath: $self->{cmdpath}\n";

}

#Find the modules for the machine from config_machines.xml
sub findModulesFromMachinesDir()
{
	my $self = shift;
	
	# Get the compiler, mpilib, machine, and debug status. 
	my $compiler = $self->{compiler};
	my $machine = $self->{machine};
	my $mpilib = $self->{mpilib};
	my $debug = $self->{debug};

	my $cmroot = $self->{configmachinesroot};
	my @modulenodes; 
	my $seqnum = 1;
	my @allmodulenodes = $cmroot->findnodes("/config_machines/machine[\@MACH=\'$machine\']/module_system/modules");
	foreach my $mod(@allmodulenodes)
	{
		# If a module set does NOT have attributes, then the intention is that 
		# these modules will be loaded regardless of compiler, mpilib, or debug status.  
		if(!$mod->hasAttributes())
		{
			my @modchildren = $mod->getChildNodes();
			foreach my $child(@modchildren)
			{
				my $action = $child->getAttribute('name');	
				my $actupon = $child->textContent();
				my $modhash = {action => $action, actupon => $actupon, seqnum => $seqnum};
				push(@modulenodes, $modhash);
				$seqnum += 1;
			}
		}
		else
		{
			my $attrmatch = 0;
			foreach my $qualifier (qw/ machine compiler mpilib debug /)
			{
				if($mod->hasAttribute($qualifier) && lc $mod->getAttribute($qualifier) eq lc $self->{$qualifier})
				{
					#print '=' x 80, "\n";
				    #print "qualifier match : $qualifier\n";
					#print "mod attribute: ", $mod->getAttribute($qualifier), "\n";
					#print "self qualifier: ", $self->{$qualifier}, "\n";
					#print '=' x 80, "\n";
					$attrmatch = 1;
				}
				elsif( $mod->hasAttribute($qualifier) && $mod->getAttribute($qualifier) =~ /^\!/)
				{
					my $negatedattr = $mod->getAttribute($qualifier);
					$negatedattr =~ s/!//g;
					#print "negated attr is: $negatedattr\n";
					#print "mod attr is ", $mod->getAttribute($qualifier), "\n";
					#print "self attr is ", $self->{$qualifier}, "\n";
					if(lc $negatedattr ne lc $self->{$qualifier})
					{
						#print "negated attributes do not match, this is a match\n";
						$attrmatch = 1;
						next;
					}
					else
					{
						#print "negated attributes do match, this is NOT a match\n";
						$attrmatch = 0;
						last;
					}

				}
				elsif( $mod->hasAttribute($qualifier) && lc $mod->getAttribute($qualifier) ne lc $self->{$qualifier})
				{
					#print '=' x 80, "\n";
				    #print "qualifier no match: $qualifier\n";
					#print "mod attribute: ", $mod->getAttribute($qualifier), "\n";
					#print "self qualifier: ", $self->{$qualifier}, "\n";
					#print '=' x 80, "\n";
					$attrmatch = 0;
					last;
				}
			}
			if($attrmatch == 1)
			{
				my @modchildren = $mod->getChildNodes();
				foreach my $child(@modchildren)
				{
					#my $action = $child->getName();
					my $action = $child->getAttribute('name');
					my $actupon = $child->textContent();	
					my $modhash = { action => $action, actupon => $actupon, seqnum => $seqnum };
					#print Dumper $modhash;
					push(@modulenodes, $modhash);
					$seqnum += 1;
				}
			}
		}
	}
	$self->{modulestoload} = \@modulenodes;
	return @modulenodes;
}

sub writeXMLFileForCase()
{
	my $self = shift;
	my $cmroot = $self->{configmachinesroot};
	my $machine = $self->{machine};
    my @modulenodes;
    my $seqnum = 1;
    my @machinenodes = $cmroot->findnodes("/config_machines/machine[\@MACH=\'$machine\']");	
	
	my $machinenode = $machinenodes[0];
	
	my $casexml = XML::LibXML::Document->new("1.0.0");
	my $newmachnode = XML::LibXML::Element->new($machinenode->nodeName);
	$newmachnode->setAttribute("MACH", $machinenode->getAttribute("MACH"));
	
	my @modulesystemnodes = $cmroot->findnodes("/config_machines/machine[\@MACH=\'$machine\']/module_system");
	foreach my $mnode(@modulesystemnodes)
	{
		$newmachnode->addChild($mnode);
	}

	my @envnodes = $cmroot->findnodes("/config_machines/machine[\@MACH=\'$machine\']/environment_variables");
	foreach my $enode(@envnodes)
	{
		$newmachnode->addChild($enode);
	}
	my @limitnodes = $cmroot->findnodes("/config_machines/machine[\@MACH=\'$machine\']/limits");
	foreach my $lnode(@limitnodes)
	{
		$newmachnode->addChild($lnode);
	}

	my $newdom = XML::LibXML::Document->new("1.0");
	$newdom->setDocumentElement($newmachnode);
	my $filepath = $self->{caseroot} . "/env_mach_specific.xml";
	$newdom->toFile($filepath, 1) || die "could not write file: ", $self->{caseroot} . ", $?\n";
}

sub findModulesForCase()
{
	my $self = shift;
	my $compiler = $self->{compiler};
	my $machine = $self->{machine};
	my $mpilib = $self->{mpilib};
	my $debug = $self->{debug};

	if( ! -e $self->{machspecificfile})
	{
		die "$self->{machspecificfile} was not found!\n";
	}
    my $parser = XML::LibXML->new(no_blanks => 1);
	my $casemoduleparser = $parser->parse_file($self->{machspecificfile});
	my @allmodulenodes = $casemoduleparser->findnodes("/machine[\@MACH=\'$machine\']/module_system/modules");

	my @foundmodules = $self->findModules(\@allmodulenodes);
	$self->{modulestoload} = \@foundmodules;
	#print Dumper $self->{modulestoload};
	return @foundmodules; 
    
}

sub findModules()
{
	my $self = shift;
	my $modulenodes = shift;
	
	my $seqnum = 1;
	my @foundmodules;
	foreach my $mod(@$modulenodes)
	{
		# If the <modules> element doesn't have any attributes, 
		# then we want to load these modules no matter what.  
		if(!$mod->hasAttributes())
		{
			my @modchildren = $mod->getChildNodes();
			
			# for every child node we find, 
			# action is the module action to take, actupon is the module 
			# we want to act upon, and the seqnum denotes the order in which the
			# module will be loaded. 
			foreach my $child(@modchildren)
			{
				#my $action = $child->getName();
				my $action = $child->getAttribute('name');
				my $actupon = $child->textContent();
				my $modhash = { action => $action, actupon => $actupon, seqnum => $seqnum} ;
				push(@foundmodules, $modhash);
				$seqnum += 1;
			} 
		}
		else
		{
			my $attrmatch = 0;
			# If the modules element has attributes, we only want to load the modules within 
			# if the attribute exists as an attribute in the modules tag, and if the attribute matches
			# the machine, compiler, etc. 
			foreach my $qualifier ( qw/ machine compiler mpilib debug/)
			{
				
				if($mod->hasAttribute($qualifier) && lc $mod->getAttribute($qualifier) eq lc $self->{$qualifier})
				{
					$attrmatch = 1;
				}
                elsif( $mod->hasAttribute($qualifier) && $mod->getAttribute($qualifier) =~ /^\!/)
                {
                    my $negatedattr = $mod->getAttribute($qualifier);
                    $negatedattr =~ s/!//g;
                    #print "negated attr is: $negatedattr\n";
                    #print "mod attr is ", $mod->getAttribute($qualifier), "\n";
                    #print "self attr is ", $self->{$qualifier}, "\n";
                    if($negatedattr ne $self->{$qualifier})
                    {
                        #print "negated attributes do not match, this is a match\n";
                        $attrmatch = 1;
                        next;
                    }
                    else
                    {
                        #print "negated attributes do match, this is NOT a match\n";
                        $attrmatch = 0;
                        last;
                    }

                }
				# if the qualifier exists as an attribute but doesn't match, skip the entire block. 
				elsif( $mod->hasAttribute($qualifier) && lc $mod->getAttribute($qualifier) ne lc $self->{$qualifier})
				{
					$attrmatch = 0;
					last;
				}
			}
			if($attrmatch == 1)
			{
				my @modchildren = $mod->getChildNodes();
				foreach my $child(@modchildren)
				{
					#my $action = $child->getName();
					my $action = $child->getAttribute('name');
					my $actupon = $child->textContent();	
					my $modhash = { action => $action, actupon => $actupon, seqnum => $seqnum };
					push(@foundmodules, $modhash);
				    $seqnum += 1;
				}
			}
		}
	}
	#print Dumper \@foundmodules;
	return @foundmodules;
}

sub loadModules()
{
    my $self = shift;
    if($self->{modulesystemtype}  eq 'module')
    {
        $self->loadModuleModules();
    }
    elsif($self->{modulesystemtype} eq 'soft')
    {
        $self->loadSoftModules();
    }
	elsif($self->{modulesystemtype} eq 'dotkit')
	{
		$self->loadDotKitModules();
	}
}

sub loadDotKitModules()
{
	my $self = shift;
	
	if(! defined $self->{modulestoload})
	{
		$self->findModulesForCase();
	}
	$self->findEnvVars();
	$self->findLimits();
	
	if(! defined $self->{cshmodulecode})
	{
        $self->getCshModuleCode();
	}
	
	my %oldenv = %ENV;
	my %newenv;
	my @output;
	my $cmd = $self->{cshmodulecode};
	$cmd .= "\nprintenv";
	
	eval { @output = qx($cmd); }; 
	chomp @output;
	foreach my $line(@output)
	{
		if(length($line) > 0)
		{
			chomp $line;
			my ($key, $value) = split('=', $line, 2);
			$newenv{$key} = $value;
		}
	}
	
	my %newbuildenv;
	
	foreach my $k(keys %newenv)
	{
		if(! defined $oldenv{$k})
		{
			$newbuildenv{$k} = $newenv{$k};
			$ENV{$k} = $newenv{$k};
		}
		if(defined $oldenv{$k} && $newenv{$k} ne $oldenv{$k})
		{
			$newbuildenv{$k} = $newenv{$k};
			$ENV{$k} = $newenv{$k};

		}
	}
	$self->writeCshModuleFile();
	$self->writeShModuleFile();
}

sub loadModuleModules()
{
	my $self = shift;
	
	if(! defined $self->{modulestoload})
	{
		$self->findModulesForCase();
	}
    $self->findEnvVars();
    $self->findLimits();
	
	my $modulestoload = $self->{modulestoload};
	
	foreach my $mod(@$modulestoload)
	{
		#print "mod seqnum: $mod->{seqnum}\n";
		#print "mod action: $mod->{action}\n";
		#print "mod actupon: $mod->{actupon}\n";
		my $cmd;
		if($mod->{action} =~ /xmlchange/)
		{
			$cmd = "./xmlchange $mod->{actupon}";
		}
		else
		{
		    $cmd = $self->{cmdpath} . " $mod->{action}  $mod->{actupon}";
		}
		print "running cmd: $cmd\n";
		eval qx($cmd);
		if($?)
		{
			warn "module cmd $cmd died with $? $!\n";
		}
	}
    my %moduleenv = %{$self->{environmentvars}};
    foreach my $key(keys %moduleenv)
    {
        my $envvalue = $moduleenv{$key};
	    if($envvalue =~ /^\$/)
		{
			$envvalue =~ s/\$//g;
			$ENV{$key} = $ENV{$envvalue};
		}
		else
		{
            $ENV{$key} = $moduleenv{$key};
		}
    }

	$self->writeCshModuleFile();
	$self->writeShModuleFile();
}


sub loadSoftModules()
{
    my $self = shift;
    if(! defined $self->{shmodulecode})
    {
        $self->getShModuleCode();
    }

    # Stash the old env here. 
    my %oldenv = %ENV;
    my %newenv;
    my @output;
    
    my $cmd = $self->{shmodulecode};
    $cmd .= "\nprintenv";
    
    eval { @output = qx($cmd); };
    chomp @output;
    foreach my $line(@output)
    {
        if(length($line) > 0)
        {
            chomp $line;
            my ($key, $value) = split('=', $line, 2);
            $newenv{$key} = $value;
        }
    }

    my %newbuildenv;

    foreach my $k(keys %newenv)
    {
        if(! defined $oldenv{$k})
        {
            $newbuildenv{$k} = $newenv{$k};
            $ENV{$k} = $newenv{$k};
        }
        if(defined $oldenv{$k} && $newenv{$k} ne $oldenv{$k})
        { 
            $newbuildenv{$k} = $newenv{$k};
            $ENV{$k} = $newenv{$k};
        }
    }
	$self->writeCshModuleFile();
	$self->writeShModuleFile();
}

sub findEnvVars()
{
	my $self = shift;
	my $machine = $self->{machine};
    my $parser = XML::LibXML->new(no_blanks => 1);
    my $xml = $parser->parse_file($self->{machspecificfile});
    my @envnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/environment_variables/env");
	
    my %envs;
	foreach my $enode(@envnodes)
	{
		my $name = $enode->getAttribute('name');
		my $value = $enode->textContent();
        $envs{$name} = $value;
	}
	
    $self->{environmentvars} = \%envs;
    
}

sub findLimits()
{
	my $self = shift;
	my $machine = $self->{machine};
    my $parser = XML::LibXML->new(no_blanks => 1);
    my $xml = $parser->parse_file($self->{machspecificfile});
    my @limitnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/limits/limit");
    
    my %limits;
    
    foreach my $lnode(@limitnodes)
    {
        my $name = $lnode->getAttribute('name');
        my $value = $lnode->getValue();
        $limits{$name} = $value;
    }
    
    #$self->{limits}
}

sub getCshModuleCode()
{
	my $self = shift;
	my $machine = $self->{machine};
	
    my $parser = XML::LibXML->new(no_blanks => 1);
    my $xml;
    if( -e $self->{machspecificfile})
    {
        $xml = $parser->parse_file($self->{machspecificfile});
    }
    else
    {
        $xml = $parser->parse_file($self->{configmachinesfile});
    }

	my @cshinitnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/init_path[\@lang=\'csh\']");
	
	die "no csh init path defined for this machine!" if !@cshinitnodes;
	foreach my $node(@cshinitnodes)
	{
		$self->{cshinitpath} = $node->textContent();
	}

	my @cshcmdnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/cmd_path[\@lang=\'csh\']");
	die "no c shell ccmd_path defined for this machine!" if ! @cshcmdnodes;
	foreach my $node(@cshcmdnodes)
	{
		$self->{cshcmdpath} = $node->textContent();
	}
	
	

my $csh =<<"START";
#!/usr/bin/env csh -f 
#===============================================================================
# Automatically generated module settings for $self->{machine}
# DO NOT EDIT THIS FILE DIRECTLY!  Please edit env_mach_specific.xml 
# in your CASEROOT. This file is overwritten every time modules are loaded!
#===============================================================================

source $self->{cshinitpath}
START
	
	if(! -e "$self->{caseroot}/env_mach_specific.xml")
	{
		$self->writeXmlFileForCase();
	}
	my $casexml = $parser->parse_file("$self->{caseroot}/env_mach_specific.xml");
	my @allmodules = $casexml->findnodes("//machine[\@MACH=\'$machine\']/module_system/modules");
	
	foreach my $mod(@allmodules)
	{
		if(!$mod->hasAttributes())
		{
			my @modchildren = $mod->getChildNodes();
			foreach my $child(@modchildren)
			{
				#my $action = $child->getName();
                my $action = $child->getAttribute('name');
				my $actupon = $child->textContent();
				$csh .= "$self->{cshcmdpath} $action $actupon\n";
			}
		}
		else
		{
			my @attrs = $mod->attributes;
	
			$csh .= "if ( ";
			while(@attrs)
			{
				my $attr = shift @attrs;
				my $name = uc($attr->getName());
				my $value = $attr->getValue();
		        if($value =~ /^\!/)
				{
					$value =~ s/\!//g;
					$csh .= "\$$name != \"$value\"";
				}
				else
				{
					$csh .= "\$$name == \"$value\"";
				}
				$csh .= " && " if(@attrs);
			}
			$csh .= " ) then\n";

			my @modchildren = $mod->getChildNodes();
			foreach my $child(@modchildren)
			{
				
				#my $action = $child->getName();
				my $action = $child->getAttribute('name');
				my $actupon = $child->textContent();
				if($action =~ /xmlchange/)
				{
					$csh .= "\t./$action $actupon\n";
				}
				else
				{
					$csh .= "\t$self->{cshcmdpath} $action $actupon\n";
				}
			}
			$csh .= "endif\n";
		}
	}
	
    my @envnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/environment_variables/env");
    if(@envnodes)
	{
        foreach my $enode(@envnodes)
        {
            my $name = $enode->getAttribute('name');
            my $value = $enode->textContent();
	    	$csh .= "setenv $name $value\n";
        }
    }

	my @limitnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/limits/limit");
    if(@limitnodes)
    {
	    foreach my $lnode(@limitnodes)
	    {
	    	my $name = $lnode->getAttribute('name');
	    	my $value = $lnode->textContent();
	    	$csh .= "limit $name $value\n";
	    }
    }
	
    $self->{cshmodulecode} = $csh;
}
sub writeCshModuleFile()
{
    my $self = shift;
    if(! defined $self->{cshmodulecode})
    {
        $self->getCshModuleCode();
    }
	open my $CSHFILE, ">", "$self->{caseroot}/.env_mach_specific.csh" || die " coult not open test.csh, $!";
	print $CSHFILE $self->{cshmodulecode};
	close $CSHFILE;
}

sub getShModuleCode()
{
    my $self = shift;
	my %cshtosh = ( "cputime" => "-t", 
                      "filesize" => "-f",
                      "datasize" => "-d", 
                      "stacksize" => "-s", 
                      "coredumpsize" => "-c", 
                      "memoryuse" => "-m", 
                      "vmemoryuse" => "-v",
                      "descriptors" => "-n", 
                      "memorylocked" => "-l",
                      "maxproc" => "-u" );
    my $machine = $self->{machine};

    #my $xml = $self->{configmachinesroot};
    my $parser = XML::LibXML->new(no_blanks => 1);
    my $xml;
    if( -e $self->{machspecificfile})
    {
        $xml = $parser->parse_file($self->{machspecificfile});
    }
    else
    {
        $xml = $parser->parse_file($self->{configmachinesfile});
    }

    my @shinitnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/init_path[\@lang=\'sh\']");

    die "no sh init path defined for this machine!" if !@shinitnodes;
    foreach my $node(@shinitnodes)
    {
        $self->{shinitpath} = $node->textContent();
    }

    my @shcmdnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/cmd_path[\@lang=\'sh\']");
    die "no c shell ccmd_path defined for this machine!" if ! @shcmdnodes;
    foreach my $node(@shcmdnodes)
    {
        $self->{shcmdpath} = $node->textContent();
    }

    my $sh =<<"START";
#!/usr/bin/env sh -f 
#===============================================================================
# Automatically generated module settings for $self->{machine}
# DO NOT EDIT THIS FILE DIRECTLY!  Please edit env_mach_specific.xml 
# in your CASEROOT. This file is overwritten every time modules are loaded!
#===============================================================================

.  $self->{shinitpath}
START

	
	my @allmodules = $xml->findnodes("//machine[\@MACH=\'$machine\']/module_system/modules");
	foreach my $mod(@allmodules)
	{
		if(! $mod->hasAttributes())
		{
			my @modchildren = $mod->getChildNodes();
			foreach my $child(@modchildren)
			{
				#my $action = $child->getName();
				my $action = $child->getAttribute('name');
				my $actupon = $child->textContent();
				#$sh .= "module $action $actupon \n";
                print "$self->{shcmdpath}  $action $actupon \n";
				$sh .= "$self->{shcmdpath} $action $actupon \n";
			}
		}
		else
		{
			my @attrs = $mod->attributes;
			
			$sh .= "if [ ";
			while(@attrs)
			{
				my $attr = shift @attrs;
				my $name = uc($attr->getName());
				my $value = $attr->getValue();
                if($value =~ /^\!/)
                {
                    $value =~ s/\!//g;
                    #$sh .= "\$$name != \"$value\"";
				    $sh .= "\"\$$name\" != \"$value\"";
                }
                else
                {
                    #$csh .= "\$$name == \"$value\"";
				    $sh .= "\"\$$name\" = \"$value\"";
                }
				$sh .= " ] && [ " if (@attrs);
			}
			$sh .= " ]\n";
			$sh .= "then\n";
	
			my @modchildren = $mod->getChildNodes();
			foreach my $child(@modchildren)
			{
                #my $action = $child->getName();
                my $action = $child->getAttribute('name');
				my $actupon = $child->textContent();
				if($action =~ /xmlchange/)
				{
					$sh .= "\t./$action $actupon\n";
				}
				else
				{
					$sh .= "\t$self->{shcmdpath} $action $actupon\n";
				}
			}
			$sh .= "fi\n";
		}
	}


    my @envnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/environment_variables/env");
    if(@envnodes)
    {
        foreach my $enode(@envnodes)
        {
            my $name = $enode->getAttribute('name');
            my $value = $enode->textContent();
            $sh .= "export $name=$value\n";
        }
    }

    my @limitnodes = $xml->findnodes("//machine[\@MACH=\'$machine\']/limits/limit");
    if(@limitnodes)
    {
        foreach my $lnode(@limitnodes)
        {
            my $name = $lnode->getAttribute('name');
            my $value = $lnode->textContent();
            print "name: $name, value: $value\n";
	    	my $shname = $cshtosh{$name};
            $sh .= "ulimit $shname $value\n";
        }
     }
    $self->{shmodulecode} = $sh;
}

sub writeShModuleFile
{
    my $self = shift;
    if(! defined $self->{shmodulecode})
    {
        $self->getShModuleCode();
    }
	open my $SHFILE, ">", "$self->{caseroot}/.env_mach_specific.sh" || die "could not open .env_mach_specific.sh, $!";
	print $SHFILE $self->{shmodulecode};
	close $SHFILE;
}
1;
