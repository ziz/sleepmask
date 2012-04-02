#!/usr/bin/env ruby
# Sleepmask
# A dumb terminal wrapper for RemGlk
# Copyright (c) 2012 Justin de Vesine
# Released under the MIT license - See README.md

require 'rubygems'
require 'yajl'
require 'yajl/json_gem'
require 'eventmachine'
require 'optparse'

STDOUT.sync = true

execpath = File.dirname(File.realdirpath(File.absolute_path(__FILE__)))
$interpreters = {
  :glulxe => File.join(execpath, '..', 'glulxe-rem', 'glulxe'),
  :nitfol => File.join(execpath, '..', 'nitfol-0.5-rem', 'remnitfol'),
  :cheapglulxe => File.join(execpath, '..', 'glulxe-rem', 'glulxe'),
  :debugcheapnitfol => File.join(execpath, '..', 'nitfol-0.5-rem', 'remnitfol') + " -i -no-spell",
  :fizmo => File.join(execpath, '..', 'fizmo-0.7.2', 'fizmo-glktermw', 'fizmo-glktermw'),
  :cheaphe => File.join(execpath, '..', 'hugo-rem', 'glk', 'heglk')
}
options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: sleepmask.rb [options] [gamefile]"
  options[:debug] = false
  options[:verbose] = false
  options[:width] = 70
  options[:height] = 24 
  options[:interpreter] = :glulxe

  opts.on('-i', '--interpreter TERP', 'Interpreter') do |terp|
    if $interpreters.has_key? terp.to_sym
      options[:interpreter] = terp.to_sym
    else
      puts "Error: bad interpreter"
      puts "Possible terps are:"
      $interpreters.each do |name, val|
        puts "    #{name}"
      end
      exit
    end
  end

  opts.on('-w', '--width WIDTH', 'Width of "screen"') do |width|
    options[:width] = width.to_i
  end

  opts.on('-r', '--height HEIGHT', 'Height of "screen"') do |height|
    options[:height] = height.to_i
  end

  opts.on('-v', '--verbose', 'Verbose output') do
    options[:verbose] = true
  end

  opts.on('-d', '--debug', 'Debugging output (even more verbose)') do
    options[:debug] = true
  end

  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
end

optparse.parse!

$options = options

$debug = options[:debug]
if options[:debug]
  options[:verbose] = true
end

if ARGV.empty?
  puts "%% No gamefile specified, exiting."
  exit
end

gamefile = ARGV[0]
gamepath = File.expand_path(gamefile)
if !File.exists? gamepath
  puts "%% No gamefile found: #{gamefile}"
  exit
end

class RemHandler < EM::Connection
  attr_reader :queue

  def initialize(q)
    @queue = q
    @gen = nil
    @windows = {}
    @inputs = []

    cb = Proc.new do |action|
      input_id = nil
      gen = nil
      msgtype = "line"
      msg = action[:msg]
      if !@inputs.empty?
        @inputs.each do |input|
          if input[:type] == "line"
            input_id = input[:id]
            gen = input[:gen]
            break
          end
        end
        @inputs.each do |input|
          if input[:type] == "char"
            msgtype = "char"
            input_id = input[:id]
            gen = input[:gen]
            break
          end
        end
      end

      if !input_id.nil?
        if msgtype == "char"
          if msg.empty?
            value = "return"
          elsif msg[0] == "/"
            parts = msg.split(' ')
            if parts.count == 1
              value = msg.slice(1)
            else
              value = parts[1]
            end
            if value == "space"
              value = " "
            end
          else
            value = msg[0]
          end
        else
          value = msg
        end
        message = {
          :type => msgtype,
          :gen => gen.to_i,
          :window => input_id.to_i,
          :value => value.to_s
        }

        if action.has_key? :savefile
          message[:savefile] = action[:savefile]
        end

        puts "%% Sending: #{message.to_json}" if $debug
        send_data(message.to_json)
      else
        puts "%% Couldn't send: #{msg}"
      end
      #send_data(msg)
      q.pop &cb
    end

    q.pop &cb
  end

  def post_init
    @parser = Yajl::Parser.new(:symbolize_keys => true)
    @parser.on_parse_complete = method(:object_parsed)
    init = {
      :type => "init",
      :gen => 0,
      :metrics => {
        :width => $options[:width],
        :height => $options[:height]
      }
    }
    send_data(init.to_json)
  end

  def run_to_s(run)
    close = false
    s = ""
    if run[:style] == "emphasized"
      run[:style] = "em"
    end

    if run[:style] == "header"
      s += "# "
    elsif run[:style] == "subheader"
      s += "## "
    elsif run[:style] == "alert"
      s += "** "
    elsif ["normal", "preformatted"].index(run[:style]).nil?
      close = true
      s += "<#{run[:style]}>"
    end
    s += "#{run[:text]}"
    if run.has_key? :hyperlink and !run[:hyperlink].empty?
      s += "< #{run[:hyperlink]} >"
    end
    if close
      s += "</#{run[:style]}>"
    end
    return s
  end

  def object_parsed(obj)
    if obj[:type] == "pass"
      puts "%% Passing." if $debug
      return
    end

    if obj[:type] == "error"
      puts "%% Critical error."
      puts "%% Message: #{obj[:message]}"
      return
    end

    if obj[:type] != "update"
      puts "%% Unknown event type: #{obj[:type]}"
      puts obj.inspect
      return
    end

    if obj.has_key? :windows
      obj[:windows].each do |window|
        puts "%% Window: #{window.inspect}" if $debug
        @windows[window[:id]] = window
        if window[:type] == "grid"
          @windows[window[:id]][:grid] = [" " * window[:width]] * window[:height]
        else
          @windows[window[:id]][:buffer] = []
        end
      end
    end

    if obj.has_key? :inputs
      @inputs = obj[:inputs]
      puts "Inputs: #{@inputs.inspect}" if $debug
    end

    if obj.has_key? :contents
      obj[:contents].each do |content|
        puts "%% Content: #{content.inspect}" if $debug
        window = @windows[content[:id]]
        if window[:type] == "grid"
          content[:lines].each do |line|
            window[:grid][line[:line]] = ""
            line[:content].each do |run| 
              window[:grid][line[:line]] += run_to_s(run)
            end
          end
          puts "%% Grid window #{content[:id]}:" if $options[:verbose]
          puts "] " + window[:grid].join("\n] ")
          puts "%% ---" if $options[:verbose]
        else
          if content.has_key? :clear and content[:clear]
            window[:buffer] = []
            puts "%% clearing window #{content[:id]}" if $options[:verbose]
          end
          if content.has_key? :text and !content[:text].empty?
            content[:text].each do |text|
              s = ""
              if text.has_key? :content and !text[:content].empty?
                text[:content].each do |run|
                  s += run_to_s(run)
                end
              end

              if text.has_key? :append and text[:append]
                window[:buffer] << "" if window[:buffer].last.nil?
                window[:buffer][-1] += s
              else
                window[:buffer] << s
              end
            end
          end
          puts window[:buffer].join("\n")
          window[:buffer] = [window[:buffer].last]
        end
      end
    end

    #ap obj

  end
  def receive_data data
    puts "%% Parser got: #{data}" if $options[:debug]
    @parser << data
  end
  def unbind
    puts "#{$options[:interpreter]} quit with exit status: #{get_status.exitstatus}"
    EM.stop
  end
end


class KeyboardHandler < EM::Connection
  include EM::Protocols::LineText2

  attr_reader :queue

  def initialize(q)
    @queue = q
    @saveflag = false
    @savecmd = nil
    @savefile = nil
  end

  def receive_line(data)
    puts "Keyboard got: '#{data}'" if $debug
    if data == "/quit" 
      puts "%% Quitting!"
      EM.stop
    end
    matches = data.match(/^\/savefile (.*)/)
    if matches
      puts "%% Setting savefile to #{matches[1]}"
      @savefile = matches[1].downcase.gsub(/[^a-z0-9]/, "")
      return
    elsif data == "/savefile"
      puts "%% Current savefile is: #{@savefile.nil? ? '<not set>' : @savefile}'"
      return
    end
    if data.downcase == "save" or data.downcase == "restore"
      if @savefile.nil?
        @saveflag = true
        @savecmd = data
        puts "%% File to #{data.downcase}:"
        return
      end
    end

    if @saveflag
      @saveflag = false
      savefile = data.downcase.gsub(/[^a-z0-9]/, "")
      puts "%% #{@savecmd.capitalize} file: #{savefile}"
      @queue.push({:msg => @savecmd, :savefile => savefile})
    else
      if !@savefile.nil?
        puts "%% sending savefile name: #{@savefile}"
        @queue.push({:msg => data, :savefile => @savefile})
        @savefile = nil
      else
        @queue.push({:msg => data})
      end
    end
  end
end


EM.run{
  q = EM::Queue.new
  puts "#{$interpreters[$options[:interpreter]]}  '#{gamepath}'"
  EM.popen("#{$interpreters[$options[:interpreter]]}  '#{gamepath}'", RemHandler, q)
  EM.open_keyboard(KeyboardHandler, q)
}


