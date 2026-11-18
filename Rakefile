require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do | t |
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Compile the page's stylesheet (tailwind/git_diff_live.css) into app/assets/builds. Run after changing a class in a view, a helper or the JavaScript."
task :css do
  sh "bundle", "exec", "tailwindcss", "--input", "tailwind/git_diff_live.css", "--output", "app/assets/builds/git_diff_live.css", "--minify"
end

task default: :test
