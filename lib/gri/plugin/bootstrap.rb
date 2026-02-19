module GRI
  module Bootstrap
    extend Bootstrap
    def layout
      <<EOS
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><%= @title %></title>
<style>
span.large {font-size: x-large;}
table.ds {margin-bottom: 2px;}
table.ds td {padding:0;background:#f9f9f9; border-collapse: separate;}
table.ds th {background:#ffd0d0;
background:linear-gradient(to bottom, #ffd8d8 0%,#ffcccc 45%,#ffc0c0 100%);
text-align:left;}
hr {border:none;border-top:1px #cccccc solid;}
</style>
</head>

<body>

<%= yield %>

</body>
</html>
EOS
    end
  end

  class Grapher
    def public_dir
      File.dirname(__FILE__) + '/../../../public'
    end

    def self.layout
      Bootstrap.layout
    end
  end

  class Cast
    def public_dir
      File.dirname(__FILE__) + '/../../../public'
    end

    def self.layout
      Bootstrap.layout
    end
  end
end
