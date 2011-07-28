#!/usr/bin/perl -w
use strict;

# OS/OS Version
my $os;
my $ver;
my $platform;
{ my $tc = `uname -s`;
  chomp($tc);
  $os = $tc;
  $tc = `uname -r`;
  chomp($tc);
  $ver = $tc;
  $tc = `uname -i`;
  chomp($tc);
  $platform = $tc;
}

print "[Operating System]:-[".$os." ".$ver."]";

# Memory Usage
my $physmem;
my $physmem_in_k;
my $mem_usage;

my $vmuse;
{ if ($os eq 'FreeBSD') {
    my $phy_tmp = `sysctl hw.realmem`;
    my @phy_tmp = split (/ +/,$phy_tmp);
    $physmem = $phy_tmp[1]/1048576;
    $physmem_in_k = $phy_tmp[1]/1024;
  } elsif ($os eq 'SunOS') {
    my $phy_tmp = `prtconf | grep '^Memory size: '`;
    my @phy_tmp = split (/ +/,$phy_tmp);
    $physmem = $phy_tmp[2];
    $physmem_in_k = $phy_tmp[2] * 1024;
  } else {
    my @tc = stat '/proc/kcore';
    my $km_tmp = $tc[7];
    $physmem = int($km_tmp/1048576);
    $physmem_in_k = int($km_tmp/1024);
  }
}
{ if ($os eq 'FreeBSD') {
    my $vmtotal = `sysctl vm.vmtotal|grep ^Real`;
    chomp $vmtotal;
    my @vmtotal = split (/ +/,$vmtotal);
    my $vmuse_in_k = substr($vmtotal[4],0,-2);
    $vmuse = int($vmuse_in_k/1024);
    $mem_usage = int($vmuse_in_k/$physmem_in_k * 1000)/10;
  } elsif ($os eq 'Linux') {
    open(IOMEM, "/proc/iomem");
    my $t_phymem = 0;
    while (<IOMEM>) {
      chomp;
      @_ = split;
      if ((($_[2] eq 'System')&&($_[3] eq 'RAM'))) {
        @_ = split('-',$_[0]);
        $t_phymem = $t_phymem + int((hex($_[1])-hex($_[0])/1024));
      }
    }
    if ($t_phymem != 0) {
      $physmem_in_k = $t_phymem/1024;
      $physmem = int($t_phymem/1048576);
    }
    close (IOMEM);
    open(MEMINFO, "/proc/meminfo");
    my $vmfree_in_k = 0;
    my $vmtotal_in_k = 0;
    while (<MEMINFO>) {
        chomp;
        @_ = split;
	if ($_[0] eq "MemTotal:") {
            $vmtotal_in_k = $_[1];
        } elsif (($_[0] eq "MemFree:")||($_[0] eq "Buffers:")||($_[0] eq "Cached:")) {
            $vmfree_in_k = $vmfree_in_k + $_[1];
        }
    }
    close(MEMINFO);
    my $vmuse_in_k = $physmem_in_k - $vmfree_in_k;
    $vmuse = int($vmuse_in_k/1024);
    $mem_usage = int($vmuse_in_k/$physmem_in_k * 1000)/10;
  } elsif ($os eq 'SunOS') {
    my $vmstat = `vmstat|tail -n 1`;
    my @vmstat = split (/ +/,$vmstat);
    my $vmfree_in_k = $vmstat[5];
    my $vmuse_in_k = $physmem_in_k - $vmfree_in_k;
    $vmuse = int($vmuse_in_k/1024);
    $mem_usage = int($vmuse_in_k/$physmem_in_k * 1000)/10;
  }
}
print " [RAM]:-[Usage: ".$vmuse."/".$physmem."MB (".$mem_usage."%)]";

# CPU Type, relies on FreeBSD's hw sysctl tree and cpuid
my $cpu_num = 0;
my $cpu_type;
my $cpu_speed;
my $cpu_L2_cache;
my $cpu;
my $gestalt;
if ($os eq 'FreeBSD') {
    { my $ncpu = `sysctl hw.ncpu`;
      chomp $ncpu;
      my @ncpu = split (/ +/,$ncpu);
      $cpu_num = $ncpu[1];
    }
    { my $cpuspeed = `sysctl hw.clockrate`;
      chomp $cpuspeed;
      my @cpuspeed = split (/ +/,$cpuspeed);
      $cpu_speed = $cpuspeed[1];
    }
    { my @cpuid = `cpuid`;
      my $t_cpuven;
      foreach (@cpuid) {
        chomp $_;
        my @line = split (/ +/,$_);
        unless (defined($line[0])) { next; }
        if ($line[0] eq "Vendor") {
          if ($line[2] eq "\"GenuineIntel\"\;") {
            $t_cpuven = "Intel";
          }
        } elsif ($line[0] eq "Model") {
          if (exists($line[4])) {
            $cpu_type = $t_cpuven." ".$line[3]." ".$line[4];
          } else {
            $cpu_type = $t_cpuven." ".$line[3];
          }
        } elsif (defined ($line[2]) && $line[2] eq "cache:") {
          chop $line[3];
          $cpu_L2_cache = $line[3];
        }
    }
  }
} elsif ($os eq 'Linux') {
  open(CPUINFO, "/proc/cpuinfo");
  while(<CPUINFO>) {
    chomp;
    if ($_ eq '') {
      next;
    }
    @_ = split;
    if ($_[0] eq 'processor') {
      $cpu_num++;
    } elsif ($_[0] eq 'clock') {
      $cpu_speed = substr($_[2],0,-3);
    } elsif ($_[0] eq 'L2') {
      $cpu_L2_cache = $_[3].'B';
    } elsif (($_[0] eq 'cpu') && ($_[1] eq ':')) {
      $cpu = $_[2];
    } elsif ($_[0] eq 'detected') {
      $gestalt = $_[3];
    } elsif (($_[0] eq 'cpu') && ($_[1] eq 'family')) {
      if ($_[3] == 15) {
        $cpu_type = 'Intel Pentium 4';
      }
    } elsif (($_[0] eq 'cpu') && ($_[1] eq 'MHz')) {
      $cpu_speed = int($_[3]);
    } elsif ($_[0] eq 'cache') {
      $cpu_L2_cache = $_[3].'KB';
    }
  }
  if (!$cpu_type && ($platform eq "ppc")) {
    if ($gestalt == '48' && $cpu eq '740/750') {
      $cpu_type = 'PowerPC G3'
    } else {
      $cpu_type = 'PowerPC '.$cpu;
    }
  }
  close(CPUINFO);
} elsif ($os eq 'SunOS') {
  $cpu_num = int(`psrinfo|wc -l`);
  my $psrinfo_speed = `psrinfo -v|grep MHz|head -n 1`;
  my @psrinfo_speed = split(/ +/, $psrinfo_speed);
  $cpu_speed = $psrinfo_speed[6];
  my $raw_cpu_type = `prtpicl -c cpu -v|grep \:family|head -n 1`;
  my @raw_cpu_type = split(/ +/, $raw_cpu_type);
  if ($raw_cpu_type[2] eq '0xf') {
    $cpu_type = 'Intel Pentium 4';
  }
  my $raw_cpu_cache = `prtpicl -c cpu -v|grep \:sectored-l2-cache-size|head -n 1`;
  my @raw_cpu_cache = split(/ +/, $raw_cpu_cache);
  # HACK - wild assed guessing ahead
  if ($raw_cpu_cache[2] eq '0x80000') {
    $cpu_L2_cache = '1024KB';
  }
}
      
print " [CPU]:-[".$cpu_num."-".$cpu_type.", ".$cpu_speed."MHz, ".$cpu_L2_cache,
	"]";

# uptime calculation
my $uptime;
my $up_days;
my $up_hours;
my $up_minutes;
my $uptime_t;
open(OLD_STDERR,">&STDERR");
open(STDERR,">/dev/null");
{ if (`which guptime`) {
	$uptime = `guptime`;
  } else {
	$uptime = `uptime`;
  }
}
# HACK - what the hell, solaris?
if ('x'.$uptime eq 'x') {
  $uptime = `uptime`;
}
open(STDERR,">&OLD_STDERR");
chomp($uptime);
{ my @xsplit = split(/ +/, $uptime);
  if (exists $xsplit[11]) {
    $up_days = $xsplit[3];
    my @tsplit = split(/:/, $xsplit[5]);
    $up_hours = $tsplit[0];
    $up_minutes = $tsplit[1];
    chop $up_minutes;
  } else {
    $up_days = 0;
    my @tsplit = split(/:/, $xsplit[3]);
    $up_hours = $tsplit[0];
    $up_minutes = $tsplit[1];
    chop $up_minutes;
  }
}
$uptime_t = $up_days*1440;
$uptime_t += $up_hours*60;
$uptime_t += $up_minutes;

# uptime records, relies on uprecords
my $upr_succ = 0;
my $rec_days;
my $rec_hours;
my $rec_minutes;
my $record_t;
open(OLD_STDERR,">&STDERR");
open(STDERR,">/dev/null");
if (`which uprecords`) {
  my @record = `uprecords -scam1`;
  chomp($record[2]);
  { my @xsplit = split(/ +/, $record[2]);
    $rec_days = $xsplit[2];
    $record_t = $rec_days*1440;
    my @tsplit = split(/:/, $xsplit[4]);
    $rec_hours = $tsplit[0];
    $record_t += $rec_hours*60;
    $rec_minutes = $tsplit[1];
    $record_t += $rec_minutes;
  }
  # another solaris hack
  if ('x'.$record[2] eq 'x') {
    $upr_succ = 0;
  } else {
    $upr_succ = 1;
  }
}
open(STDERR,">&OLD_STDERR");

print " [Uptime]:-[";
if ($upr_succ ==1) {
  print"Now: ";
}
print $up_days."days ".$up_hours."hrs ".$up_minutes."mins";
if ($upr_succ == 1) {
  if ($record_t > $uptime_t) {
    print "]-[Record: ".$rec_days."days ".$rec_hours."hours ".$rec_minutes,
      "mins]";
  } else {
	print " (Record)";
  }
}
print "]";

# disk usage
my @df = `df -Phl`;
my @mount = `mount`;
my %drive_infos;
my @drives;
my %opt_excludes = ('devfs'=>1, 'nullfs'=>1, 'fdescfs'=>1, 'procfs'=>1, 'tmpfs'=>1);
my %point_excludes = ('/dev/shm'=>1, '/dev'=>1, '/run'=>1, '/media'=>1, '/sys/fs/cgroup'=>1);
my $total_used_k = 0;
my $total_k = 0;
foreach (@mount) {
	chomp;
	my @xsplit = split(/ +/);
	my $tsplit = join(" ",@xsplit[3...$#xsplit]);
	my @tsplit = split(/, /,substr(substr($tsplit,1),0,-1));
	foreach (@tsplit) {
		if (exists($opt_excludes{$_})) {
			$point_excludes{$xsplit[2]} = 1;
		}
	}
}
shift(@df);
foreach (@df) {
	chomp;
	my @xsplit = split(/ +/);
	# HACK
	if ($xsplit[0] eq 'rootfs') {
		next;
	}
	unless (exists($point_excludes{$xsplit[5]})) {
		push(@drives,$xsplit[5]);
		# chop /dev/ off
		@drive_infos{$xsplit[5]} = [substr($xsplit[0], 5), 
			$xsplit[1], $xsplit[2]];
		my @kd = `df -Pk $xsplit[5]`;
		my @ksplit = split(/ +/,$kd[1]);
		shift(@ksplit);
		$total_used_k = $total_used_k + $ksplit[1];
		$total_k = $total_k + $ksplit[2];
	}
}

print " [Free Space (Total ".int($total_used_k/1048576)."G/",
  int($total_k/1048576)."G) (".int(($total_used_k/$total_k)*100)."% use)]:";
foreach (@drives) {
	print "-[".$drive_infos{$_}[0]."(".$_.") ".$drive_infos{$_}[2]."/",
		$drive_infos{$_}[1]."]";
}

# X configuration (if available)
if (exists($ENV{'DISPLAY'})) {
	my $x_dimensions;
	my $x_depth;
	my @xdpyinfo = `xdpyinfo`;
	foreach (@xdpyinfo) {
		chomp;
		my @xsplit = split(/ +/);
		unless (defined($xsplit[0]) && defined($xsplit[1])) { next; }
		if ($xsplit[1] eq "dimensions:") {
			$x_dimensions = $xsplit[2];
		} elsif ($xsplit[1] eq "depth" && $xsplit[3] eq "root") {
			$x_depth = $xsplit[5];
		}
	}
	print " [Resolution]:-[".$x_dimensions." ".$x_depth."bit]";
}

print "\n";
