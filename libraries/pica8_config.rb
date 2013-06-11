#
#  Copyright (c) 2013, Internet Initiative Japan Inc.
#  All rights reserved.
# 
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
# 
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS. AND CONTRIBUTORS
#  ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
#  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#  PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS
#  BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.

require 'pty'
require 'expect'
require 'fileutils'

if $0 == __FILE__
  $:.unshift File.dirname(__FILE__)
  require 'config_manager'
  require 'pica8_config'
end

class Pica8Config
  CMD_SHOW_RUN = "/pica/bin/shell/show_running_config.sh"
  CMD_PICA_SH =	"/pica/bin/pica_sh"
  OUT_PATH_PREFIX = "/pica/config/root"
  PICA8_CONF_RUNNING = "/pica/config/pica.conf"
  PTY_DEBUG = false

  include ConfigManager

  def initialize
    @parse_state = :initial
    @conf = Hash.new
  end

  # Apply candidate-config to pica8 system
  def config_apply(conf)
    tmp_conf_name = "chef_" + $$.to_s
    config_raw_put(conf, tmp_conf_name)
    PTY.spawn(CMD_PICA_SH) do |i, o|
      o.sync = true
      begin
        i.expect(/> /, 10) do |line|
          raise if line == nil
          pty_debug("in", line)
          cmd = "configure"
          o.puts cmd
          pty_debug("out", [cmd])
          i.gets
        end
        i.expect(/# /, 10) do |line|
          raise if line == nil
          pty_debug("in", line)
          cmd = "load #{tmp_conf_name}"
          o.puts cmd
          pty_debug("out", [cmd])
          i.gets
        end
        i.expect(/# /, 10) do |line|
          raise if line.join.include?("ERROR: ")
          pty_debug("in", line)
          cmd = "commit"
          o.puts cmd
          pty_debug("out", [cmd])
          i.gets
        end
        i.expect(/# /, 10) do |line|
          raise if line == nil
          pty_debug("in", line)
          cmd = "exit"
          o.puts cmd
          pty_debug("out", [cmd])
        end
      rescue
        puts "Error: apply config."
        File.unlink(File.join(OUT_PATH_PREFIX, tmp_conf_name))
        return
      ensure
        # XXX pica8 workaround a bug
        FileUtils.cp(File.join(OUT_PATH_PREFIX, tmp_conf_name), PICA8_CONF_RUNNING)

        File.unlink(File.join(OUT_PATH_PREFIX, tmp_conf_name))
      end
    end
  end

  def config_raw_get
    @seq = Array.new
    IO.popen(CMD_SHOW_RUN) do |r|
      r.each_line do |line|
        terms = line.chomp.lstrip.split(/\s+/)
        terms.each do |t|
          @seq.push(t)
        end
      end
    end
    config_parse
    @conf
  end

  def config_raw_put(conf, file_path = nil)
    if file_path != nil
      @of = open(File.join(OUT_PATH_PREFIX, file_path), "w")
    else
      @of = STDOUT
    end
    @of.puts "/*XORP Configuration File, v1.0*/"
    config_raw_put0(conf, 0)
    @of.close if @of.instance_of?(File)
  end

  private
  def pty_debug(prefix, strings)
    return if PTY_DEBUG != true
    puts "debug: pty-#{prefix}=#{strings}"
  end

  def indent_make(offset)
    @of.print " " * offset
  end

  def indent_add(offset)
    offset + 4
  end

  def config_raw_put0(conf, indent)
    conf.each_key do |k|
      if conf[k].instance_of?(Hash)
        indent_make(indent)
        k.split(':').each do |e|
          @of.print "#{e} "
        end
        @of.puts "{"
        config_raw_put0(conf[k], indent_add(indent))
        indent_make(indent)
        @of.puts "}"
      else
        indent_make(indent)
        # XXX void param
        if conf[k][0] == ':'
          @of.puts "#{k} #{conf[k][1..-1]}"
        else
          @of.puts "#{k}: #{conf[k]}"
        end
      end
    end
  end

  def config_parse
    stack = [@conf]
    prev_term = nil
    @seq.each_with_index do |term, idx|
      # Comment
      if term.include?('/*')
        @parse_state = :comment
        next
      end
      if term.include?('*/')
        @parse_state = :defs
        next
      end
      if @parse_state == :comment
        next
      end

      # Hash
      if term == '{'
        @parse_state = :hash_def
        new_leaf = Hash.new
        key_str = ""
        if @seq[idx-2] == '}' or @seq[idx-2] == '{' or stack.length == 1 or
            @seq[idx-3][-1] == ':'
          key_str = @seq[idx-1]
        else
          key_str = "#{@seq[idx-2]}:#{@seq[idx-1]}"
        end
        stack[-1][key_str] = new_leaf
        stack.push(new_leaf)
        @parse_state = :defs
        next
      end
      if term == '}'
        stack.pop
        next
      end

      # Defs
      if term[-1] == ':'
        @parse_state = :tuple
        prev_term = term[0...-1]
        next
      end
      if @parse_state == :tuple
        stack[-1][prev_term] = term
        @parse_state = :defs
      end

      prev_term = term
    end
  end
end

if $0 == __FILE__
  #test
  l3swconf = Pica8Config.new
  conf = l3swconf.config_raw_get

  conf_current = conf['system']['hostname']
  conf_candidate =node['l3sw']['system']['hostname'].slice!(0).chop!
end
