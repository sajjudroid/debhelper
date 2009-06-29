# Defines debhelper build system class interface and implementation
# of common functionality.
#
# Copyright: © 2008-2009 Modestas Vainius
# License: GPL-2+

package Debian::Debhelper::Buildsystem;

use strict;
use warnings;
use Cwd ();
use File::Spec;
use Debian::Debhelper::Dh_Lib;

# Cache DEB_BUILD_GNU_TYPE value. Performance hit of multiple
# invocations is noticable when listing build systems.
our $DEB_BUILD_GNU_TYPE = dpkg_architecture_value("DEB_BUILD_GNU_TYPE");

# Build system name. Defaults to the last component of the class
# name. Do not override this method unless you know what you are
# doing.
sub NAME {
	my $this=shift;
	my $class = ref($this) || $this;
	if ($class =~ m/^.+::([^:]+)$/) {
		return $1;
	}
	else {
		error("ınvalid build system class name: $class");
	}
}

# Description of the build system to be shown to the users.
sub DESCRIPTION {
	error("class lacking a DESCRIPTION");
}

# Default build directory. Can be overriden in the derived
# class if really needed.
sub DEFAULT_BUILD_DIRECTORY {
	"obj-" . $DEB_BUILD_GNU_TYPE;
}

# Constructs a new build system object. Named parameters:
# - sourcedir-     specifies source directory (relative to the current (top)
#                  directory) where the sources to be built live. If not
#                  specified or empty, defaults to the current directory.
# - builddir -     specifies build directory to use. Path is relative to the
#                  current (top) directory. If undef or empty,
#                  DEFAULT_BUILD_DIRECTORY directory will be used. 
# Derived class can override the constructor to initialize common object
# parameters. Do NOT use constructor to execute commands or otherwise
# configure/setup build environment. There is absolutely no guarantee the
# constructed object will be used to build something. Use pre_building_step(),
# $build_step() or post_building_step() methods for this.
sub new {
	my ($class, %opts)=@_;

	my $this = bless({ sourcedir => '.',
	                   builddir => undef, }, $class);

	if (exists $opts{sourcedir}) {
		# Get relative sourcedir abs_path (without symlinks)
		my $curdir = Cwd::getcwd();
		my $abspath = Cwd::abs_path($opts{sourcedir});
		if (! -d $abspath || $abspath !~ /^\Q$curdir\E/) {
			error("invalid or non-existing path to the source directory: ".$opts{sourcedir});
		}
		$this->{sourcedir} = File::Spec->abs2rel($abspath, $curdir);
	}
	if (exists $opts{builddir}) {
		$this->_set_builddir($opts{builddir});
	}
	return $this;
}

# Private method to set a build directory. If undef, use default.
# Do $this->{builddir} = undef or pass $this->get_sourcedir() to
# unset the build directory.
sub _set_builddir {
	my $this=shift;
	my $builddir=shift;
	$this->{builddir} = ($builddir) ? $builddir : $this->DEFAULT_BUILD_DIRECTORY;

	# Canonicalize. If build directory ends up the same as source directory, drop it
	if (defined $this->{builddir}) {
		$this->{builddir} = $this->_canonpath($this->{builddir});
		if ($this->{builddir} eq $this->get_sourcedir()) {
			$this->{builddir} = undef;
		}
	}
	return $this->{builddir};
}

# This instance method is called to check if the build system is able
# to auto build a source package. Additional argument $step describes
# which operation the caller is going to perform (either configure,
# build, test, install or clean). You must override this method for the
# build system module to be ever picked up automatically. This method is
# used in conjuction with @Dh_Buildsystems::BUILDSYSTEMS.
#
# This method is supposed to be called inside the source root directory.
# Use $this->get_buildpath($path) method to get full path to the files
# in the build directory.
sub check_auto_buildable {
	my $this=shift;
	my ($step) = @_;
	return 0;
}

# Derived class can call this method in its constructor
# to enforce in source building even if the user requested otherwise.
sub enforce_in_source_building {
	my $this=shift;
	if ($this->get_builddir()) {
		$this->{warn_insource} = 1;
		$this->{builddir} = undef;
	}
}

# Derived class can call this method in its constructor to *prefer*
# out of source building. Unless build directory has already been
# specified building will proceed in the DEFAULT_BUILD_DIRECTORY or
# the one specified in the 'builddir' named parameter (which may
# match the source directory). Typically you should pass @_ from
# the constructor to this call.
sub prefer_out_of_source_building {
	my $this=shift;
	my %args=@_;
	if (!defined $this->get_builddir()) {
		if (!$this->_set_builddir($args{builddir}) && !$args{builddir}) {
			# If we are here, DEFAULT_BUILD_DIRECTORY matches
			# the source directory, building might fail.
			error("default build directory is the same as the source directory." .
			      " Please specify a custom build directory");
		}
	}
}

# Derived class can call this method in its constructor to *enforce*
# out of source building even if the user didn't request it.
# Build directory is set to DEFAULT_BUILD_DIRECTORY or building
# fails if it is not possible to set it
sub enforce_out_of_source_building {
	my $this=shift;
	$this->prefer_out_of_source_building();
}

# Enhanced version of File::Spec::canonpath. It collapses ..
# too so it may return invalid path if symlinks are involved.
# On the other hand, it does not need for the path to exist.
sub _canonpath {
	my ($this, $path)=@_;
	my @canon;
	my $back=0;
	for my $comp (split(m%/+%, $path)) {
		if ($comp eq '.') {
			next;
		}
		elsif ($comp eq '..') {
			if (@canon > 0) { pop @canon; }  else { $back++; }
		}
		else {
			push @canon, $comp;
		}
	}
	return (@canon + $back > 0) ? join('/', ('..')x$back, @canon) : '.';
}

# Given both $path and $base are relative to the same directory,
# converts and returns path of $path being relative the $base.
sub _rel2rel {
	my ($this, $path, $base, $root)=@_;
	$root = "/tmp" if !defined $root;
	
	return File::Spec->abs2rel(
	    File::Spec->rel2abs($path, $root),
	    File::Spec->rel2abs($base, $root)
	);
}

# Get path to the source directory
# (relative to the current (top) directory)
sub get_sourcedir {
	my $this=shift;
	return $this->{sourcedir};
}

# Convert path relative to the source directory to the path relative
# to the current (top) directory.
sub get_sourcepath {
	my ($this, $path)=@_;
	return File::Spec->catfile($this->get_sourcedir(), $path);
}

# Get path to the build directory if it was specified
# (relative to the current (top) directory). undef if the same
# as the source directory.
sub get_builddir {
	my $this=shift;
	return $this->{builddir};
}

# Convert path that is relative to the build directory to the path
# that is relative to the current (top) directory.
# If $path is not specified, always returns build directory path
# relative to the current (top) directory regardless if builddir was
# specified or not.
sub get_buildpath {
	my ($this, $path)=@_;
	my $builddir = $this->get_builddir() || $this->get_sourcedir();
	if (defined $path) {
		return File::Spec->catfile($builddir, $path);
	}
	return $builddir;
}

# When given a relative path to the source directory, converts it
# to the path that is relative to the build directory. If $path is
# not given, returns a path to the source directory that is relative
# to the build directory.
sub get_source_rel2builddir {
	my $this=shift;
	my $path=shift;

	my $dir = '.';
	if ($this->get_builddir()) {
		$dir = $this->_rel2rel($this->get_sourcedir(), $this->get_builddir());
	}
	if (defined $path) {
		return File::Spec->catfile($dir, $path);
	}
	return $dir;
}

# When given a relative path to the build directory, converts it
# to the path that is relative to the source directory. If $path is
# not given, returns a path to the build directory that is relative
# to the source directory.
sub get_build_rel2sourcedir {
	my $this=shift;
	my $path=shift;

	my $dir = '.';
	if ($this->get_builddir()) {
		$dir = $this->_rel2rel($this->get_builddir(), $this->get_sourcedir());
	}
	if (defined $path) {
		return File::Spec->catfile($dir, $path);
	}
	return $dir;
}

# Creates a build directory.
sub mkdir_builddir {
	my $this=shift;
	if ($this->get_builddir()) {
		doit("mkdir", "-p", $this->get_builddir());
	}
}

sub _cd {
	my ($this, $dir)=@_;
	if (! $dh{NO_ACT}) {
		verbose_print("cd $dir");
		chdir $dir or error("error: unable to chdir to $dir");
	}
}

# Changes working directory to the source directory (if needed),
# calls doit(@_) and changes working directory back to the top
# directory.
sub doit_in_sourcedir {
	my $this=shift;
	if ($this->get_sourcedir() ne '.') {
		my $sourcedir = $this->get_sourcedir();
		my $curdir = Cwd::getcwd();
		$this->_cd($sourcedir);
		doit(@_);
		$this->_cd($this->_rel2rel($curdir, $sourcedir, $curdir));
	}
	else {
		doit(@_);
	}
	return 1;
}

# Changes working directory to the build directory (if needed),
# calls doit(@_) and changes working directory back to the top
# directory.
sub doit_in_builddir {
	my $this=shift;
	if ($this->get_buildpath() ne '.') {
		my $buildpath = $this->get_buildpath();
		my $curdir = Cwd::getcwd();
		$this->_cd($buildpath);
		doit(@_);
		$this->_cd($this->_rel2rel($curdir, $buildpath, $curdir));
	}
	else {
		doit(@_);
	}
	return 1;
}

# In case of out of source tree building, whole build directory
# gets wiped (if it exists) and 1 is returned. If build directory
# had 2 or more levels, empty parent directories are also deleted.
# If build directory does not exist, nothing is done and 0 is returned.
sub rmdir_builddir {
	my $this=shift;
	my $only_empty=shift;
	if ($this->get_builddir()) {
		my $buildpath = $this->get_buildpath();
		if (-d $buildpath && ! $dh{NO_ACT}) {
			my @spdir = File::Spec->splitdir($this->get_build_rel2sourcedir());
			my $peek;
			if (!$only_empty) {
				doit("rm", "-rf", $buildpath);
				pop @spdir;
			}
			# If build directory had 2 or more levels, delete empty
			# parent directories until the source directory level.
			while (($peek=pop(@spdir)) && $peek ne '.' && $peek ne '..') {
				last if ! rmdir($this->get_sourcepath(File::Spec->catdir(@spdir, $peek)));
			}
		}
		return 1;
	}
	return 0;
}

# Instance method that is called before performing any step (see below).
# Action name is passed as an argument. Derived classes overriding this
# method should also call SUPER implementation of it.
sub pre_building_step {
	my $this=shift;
	my ($step)=@_;

	# Warn if in source building was enforced but build directory was
	# specified. See enforce_in_source_building().
	if ($this->{warn_insource}) {
		warning("warning: " . $this->NAME() .
		    " does not support building out of source tree. In source building enforced.");
		delete $this->{warn_insource};
	}
}

# Instance method that is called after performing any step (see below).
# Action name is passed as an argument. Derived classes overriding this
# method should also call SUPER implementation of it.
sub post_building_step {
	my $this=shift;
	my ($step)=@_;
}

# The instance methods below provide support for configuring,
# building, testing, install and cleaning source packages.
# In case of failure, the method may just error() out.
#
# These methods should be overriden by derived classes to
# implement build system specific steps needed to build the
# source. Arbitary number of custom step arguments might be
# passed. Default implementations do nothing.
sub configure {
	my $this=shift;
}

sub build {
	my $this=shift;
}

sub test {
	my $this=shift;
}

# destdir parameter specifies where to install files.
sub install {
	my $this=shift;
	my $destdir=shift;
}

sub clean {
	my $this=shift;
}

1