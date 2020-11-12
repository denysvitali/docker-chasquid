require "fileinto";
if header :contains ["X-Spam-Action"] "add header" {
  fileinto "Junk";
  stop;
}

if header :contains ["X-Spam-Action"] "reject" {
  discard;
  stop;
}
