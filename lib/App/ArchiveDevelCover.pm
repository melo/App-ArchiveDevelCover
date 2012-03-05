package App::ArchiveDevelCover;
use 5.010;
use Moose;
use MooseX::Types::Path::Class;
use DateTime;
use File::Copy;
use HTML::TableExtract;

# ABSTRACT: Archive Devel::Cover reports
our $VERSION = '1.000';

with 'MooseX::Getopt';

has [qw(from to)] => (is=>'ro',isa=>'Path::Class::Dir',coerce=>1,required=>1,);
has 'project' => (is => 'ro', isa=>'Str', lazy_build=>1);
sub _build_project {
    my $self = shift;
    my @list = $self->from->parent->dir_list;
    return $list[-1] || 'unknown project';
}
has 'coverage_html' => (is=>'ro',isa=>'Path::Class::File',lazy_build=>1,traits=> ['NoGetopt']);
sub _build_coverage_html {
    my $self = shift;
    if (-e $self->from->file('coverage.html')) {
        return $self->from->file('coverage.html');
    }
    else {
        say "Cannot find 'coverage.html' in ".$self->from.'. Aborting';
        exit;
    }
}
has 'runtime' => (is=>'ro',isa=>'DateTime',lazy_build=>1,traits=> ['NoGetopt'],);
sub _build_runtime {
    my $self = shift;
    return DateTime->from_epoch(epoch=>$self->coverage_html->stat->mtime);
}
has 'archive_html' => (is=>'ro',isa=>'Path::Class::File',lazy_build=>1,traits=> ['NoGetopt']);
sub _build_archive_html {
    my $self = shift;
    unless (-e $self->to->file('index.html')) {
        my $tpl = $self->_archive_template;
        my $fh = $self->to->file('index.html')->openw;
        print $fh $tpl;
        close $fh;
    }
    return $self->to->file('index.html');
}
has 'archive_db' => (is=>'ro',isa=>'Path::Class::File',lazy_build=>1,traits=> ['NoGetopt']);
sub _build_archive_db {
    my $self = shift;
    return $self->to->file('archive_db');
}
has 'previous_stats' => (is=>'ro',isa=>'ArrayRef',lazy_build=>1,traits=>['NoGetopt']);
sub _build_previous_stats {
    my $self = shift;
    if (-e $self->archive_db) {
        my $dbr = $self->archive_db->openr;
        my @data = <$dbr>; # probably better to just get last line...
        my @prev = split(/;/,$data[-1]);
        return \@prev;
    }
    else {
        return [undef,0,0,0];
    }
}

sub run {
    my $self = shift;
    $self->archive;
    $self->update_index;
}

sub archive {
    my $self = shift;

    my $from = $self->from;
    my $target = $self->to->subdir($self->runtime->iso8601);

    if (-e $target) {
        say "This coverage report has already been archived.";
        exit;
    }

    $target->mkpath;
    my $target_string = $target->stringify;

    while (my $f = $from->next) {
        next unless $f=~/\.(html|css)$/;
        copy($f->stringify,$target_string) || die "Cannot copy $from to $target_string: $!";
    }

    say "archived coverage reports at $target_string";
}

sub update_index {
    my $self = shift;

    my $te = HTML::TableExtract->new( headers => [qw(stm sub total)] );
    $te->parse(scalar $self->coverage_html->slurp);
    my $rows =$te->rows;
    my $last_row = $rows->[-1];

    $self->update_archive_html($last_row);
    $self->update_archive_db($last_row);
}

sub update_archive_html {
    my ($self, $last_row) = @_;

    my $prev_stats = $self->previous_stats;
    my $runtime = $self->runtime;
    my $date = $runtime->ymd('-').' '.$runtime->hms;
    my $link = $runtime->iso8601."/coverage.html";

    my $new_stat = qq{\n<tr><td><a href="$link">$date</a></td>};
    foreach my $val (@$last_row) {
        my $style;
        given ($val) {
            when ($_ <  75) { $style = 'c0' }
            when ($_ <  90) { $style = 'c1' }
            when ($_ <  100) { $style = 'c2' }
            when ($_ >= 100) { $style = 'c3' }
        }
        $new_stat.=qq{<td class="$style">$val</td>};
    }
    my $prev_total = $prev_stats->[3];
    my $this_total = $last_row->[-1];
    if ($this_total == $prev_total) {
        $new_stat.=qq{<td class="c3">=</td>};
    }
    elsif ($this_total > $prev_total) {
        $new_stat.=qq{<td class="c3">+</td>};
    }
    else {
        $new_stat.=qq{<td class="c0">-</td>};
    }

    $new_stat.="</tr>\n";

    my $archive = $self->archive_html->slurp;
    $archive =~ s/(<!-- INSERT -->)/$1 . $new_stat/e;

    my $fh = $self->archive_html->openw;
    print $fh $archive;
    close $fh;

    unless (-e $self->to->file('cover.css')) {
         copy($self->from->file('cover.css'),$self->to->file('cover.css')) || warn "Cannot copy cover.css: $!";
    }
}

sub update_archive_db {
    my ($self, $last_row) = @_;
    my $dbw = $self->archive_db->open(">>") || warn "Can't write archive.db: $!";
    say $dbw join(';',$self->runtime->iso8601,@$last_row);
    close $dbw;
}

sub _archive_template {
    my $self = shift;
    my $name = $self->project;
    my $class = ref($self);
    my $version = $class->VERSION;
    return <<"EOTMPL";
<!DOCTYPE html
     PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<!-- This file was generated by $class version $version -->
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
    <meta http-equiv="Content-Language" content="en-us"></meta>
    <link rel="stylesheet" type="text/css" href="cover.css"></link>
    <title>Test Coverage Archive for $name</title>
</head>
<body>

<body>
<h1>Test Coverage Archive for $name</h1>

<table>
<tr><th>Coverage Report</th><th>stmt</th><th>sub</th><th>total</th><th>Trend</th></tr>
<!-- INSERT -->
</table>

<p>Generated by <a href="http://metacpan.org/module/$class">$class</a> version $version.</p>

</body>
</html>
EOTMPL
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 SYNOPSIS

Backend for the C<archive_devel_cover.pl> command. See L<archive_devel_cover.pl> and/or C<perldoc archive_devel_cover.pl> for details.

