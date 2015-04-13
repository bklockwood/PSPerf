
#using https://github.com/shawnbot/sparky

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.PARAMETER FilePath
The full path and name of file to write
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Write-SparkyPageHeader
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=0)][string]$FilePath
    )

    Begin{}
    Process
    {
        $PageHead = @"
<!DOCTYPE html>
<html>
    <head>
        <title>Sparky</title>
        <script type="text/javascript" src="https://rawgit.com/shawnbot/sparky/master/lib/raphael/raphael-min.js"></script>
        <script type="text/javascript" src="https://rawgit.com/shawnbot/sparky/master/src/sparky.js"></script>
        <style type="text/css">
            html, body {
                margin: 0;
                padding: 0;
            }

            body {
                font-family: "Hoefler Text", "Times New Roman", Georgia, serif;
                font-size: 18px;
                line-height: 23px;
                padding: 2em 3em;
            }

            a:link, a:visited {
                color: inherit;
                text-decoration: underline;
            }

            span.sparkline {
                display: inline-block;
                <!--width: 5em;
                height: 15px;
                margin: 0 .2em;-->
                vertical-align: middle;
            }

            label, var {
                font-family: "Trebuchet MS", "Arial Rounded MT Bold", sans-serif;
                font-style: normal;
                font-weight: bold;
                vertical-align: inherit;
                <!--font-size: 80%;-->
            }

            varcpu {
                color: Brown;
            }

            varmem {
                color: blue;
                vertical-align: inherit;
            }

            vardisk {
                color: green;
                vertical-align: inherit;
            }

            varnet {
                color: purple;
                vertical-align: inherit;
            }

            p {
                margin: 0 0 1em 0;
            }

            p.caption {
                font-size: 90%;
                font-style: italic;
            }

            h1, h2, h3, h4, h5, h6 {
                font-style: italic;
                font-weight: normal;
            }

            h3 {
                float: left;
                display: inline;
                font-size: inherit;
                line-height: inherit;
                margin: 0 .75em 0 0;
            }

            blockquote {
                color: #333;
                font-size: 90%;
            }

            blockquote small {
                text-align: right;
                display: block;
            }

            *.fw {
                font-variant: small-caps;
            }

            .warning {
                background-color: #ffc;
                margin: .2em 0;
            }

            .tftable {
                layout: auto;
                font-size:20px;
                color:#333333;
                border-width: 1px;
                border-color: #a9a9a9;
                border-collapse: collapse;
            }
            .tftable th {
                font-size:20px;
                background-color:#E6E6E6;
                border-width: 1px;
                padding: 8px;
                border-style: solid;
                border-color: #a9a9a9;
                text-align:left;
            }
            .tftable tr {
                background-color:#FFFFFF;
            }
            .tftable td {
                font-size:20px;
                border-width: 1px;
                padding: 0px;
                border-style: solid;
                border-color: #a9a9a9;

            }
        </style>
    </head>
    <body>
    <table class="tftable" border="1">
        <th></th>
        <th>cpu</th>
        <th>mem</th>
        <th>disk</th>
        <th>net</th>
"@

        out-file -InputObject $PageHead -FilePath $FilePath -Encoding unicode -Force
    }
    End{}

}

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.PARAMETER FilePath
The full path and name of file to write
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Write-SparkyPageFooter
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=0)][string]$FilePath
    )

    Begin{}
    Process
    {
        $PageFoot = @"
        </table>
        <script type="text/javascript" defer>
            sparky.presets.set("big", {
                width: 450,
                height: 100,
                padding: 10,
                line_stroke: "red",
                line_stroke_width: 2,
                dot_radius: function(d, i) {
                    return this.last ? 5 : 0;
                },
                dot_fill: "red",
                dot_stroke: "white",
                dot_stroke_width: 1
            });

            sparky.presets.set("cpu", {
                width: 150,
                height: 65,
                padding: 10,
                line_stroke: "Brown",
                line_stroke_width: 1,
                dot_radius: function(d, i) {
                    return this.last ? 5 : 0;
                },
                range_min: "1",
                range_max: "40",
                range_fill: "LightGray",
                dot_fill: "Red",
                dot_stroke: "white",
                dot_stroke_width: 1
            });


            sparky.presets.set("mem", {
                width: 150,
                height: 65,
                padding: 10,
                line_stroke: "blue",
                line_stroke_width: 1,
                dot_radius: function(d, i) {
                    return this.last ? 5 : 0;
                },
                range_min: "1",
                range_max: "40",
                range_fill: "LightGray",
                dot_fill: "red",
                dot_stroke: "white",
                dot_stroke_width: 1
            });


            sparky.presets.set("disk", {
                width: 150,
                height: 65,
                padding: 10,
                line_stroke: "green",
                line_stroke_width: 1,
                dot_radius: function(d, i) {
                    return this.last ? 5 : 0;
                },
                range_min: "1",
                range_max: "40",
                range_fill: "LightGray",
                dot_fill: "red",
                dot_stroke: "white",
                dot_stroke_width: 1
            });


            sparky.presets.set("net", {
                width: 150,
                height: 65,
                padding: 10,
                line_stroke: "purple",
                line_stroke_width: 1,
                dot_radius: function(d, i) {
                    return this.last ? 5 : 0;
                },
                range_min: "1",
                range_max: "40",
                range_fill: "LightGray",
                dot_fill: "red",
                dot_stroke: "white",
                dot_stroke_width: 1
            });

            sparky.presets.set("rainbow", {
                padding: 5,
                line_stroke: "none",
                dot_radius: function() {
                    return 1.5 + Math.random() * 3.5;
                },
                dot_fill: function() {
                    var r = (~~(Math.random() * 16)).toString(16),
                        g = (~~(Math.random() * 16)).toString(16),
                        b = (~~(Math.random() * 16)).toString(16);
                    return ["#", r, g, b].join("");
                }
            });

            var sparks = document.querySelectorAll(".sparkline"),
                len = sparks.length;
            for (var i = 0; i < len; i++) {
                var el = sparks[i],
                    data = sparky.parse.numbers(el.getAttribute("data-points")),
                    preset = sparky.presets.get(el.getAttribute("data-preset")),
                    options = sparky.util.getElementOptions(el, preset);
                sparky.sparkline(el, data, options);
            }
        </script>

    </body>
</html>
"@

        out-file -InputObject $PageFoot -FilePath $FilePath -Encoding unicode -Append -NoClobber
    }
    End{}

}

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.PARAMETER Param1
Help for Param1
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Get-RandomArray
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=0)][Int]$ArrayLength
    )

    Begin{}
    Process
    {
        $randarray = @()
        $i = 1
        while ($i -le $ArrayLength)
        { 
            $rand = Get-Random -min 1 -max 100
            $randarray += $rand    
            $i++
        }
        $result = $randarray -join(",")
        $result
    }
    End{}
}

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.PARAMETER Param1
Help for Param1
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Write-SparkyPageLine
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=0)][string]$LineName,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=1)][string]$cpu,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=2)][string]$mem,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=3)][string]$disk,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=4)][string]$net,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=5)][string]$FilePath
    )

    Begin{}
    Process
    {
        [string]$Line = "`t<tr>`r`n"
        [string]$Line += "`t<td>$LineName </td>`r`n"

        [string]$Line += "`t<td> <span class=""sparkline"" `r`n" 
        [string]$Line += "`tdata-preset=""cpu"" `r`n"
        [string]$Line += "`tdata-points = ""$cpu"" >`r`n " 
        [string]$Line += "`t<varcpu>12</varcpu> `r`n"       
        [string]$Line += "`t</span> `r`n" 
        [string]$Line += "`r`n"

        [string]$Line += "`t<td> <span class=""sparkline"" `r`n" 
        [string]$Line += "`tdata-preset=""mem"" `r`n"
        [string]$Line += "`tdata-points = ""$mem"" > `r`n"
        [string]$Line += "`t<varmem>12</varmem> `r`n"
        [string]$Line += "`t</span> </td>`r`n"
        [string]$Line += "`r`n"

        [string]$Line += "`t<td> <span class=""sparkline"" `r`n"
        [string]$Line += "`tdata-preset=""disk"" `r`n"
        [string]$Line += "`tdata-points = ""$disk"" > `r`n"
        [string]$Line += "`t<vardisk>12</vardisk> `r`n"
        [string]$Line += "`t</span> </td>`r`n"
        [string]$Line += "`r`n"

        [string]$Line += "`t<td> <span class=""sparkline"" `r`n"       
        [string]$Line += "`tdata-preset=""net"" `r`n"
        [string]$Line += "`tdata-points = ""$net"" > `r`n"
        [string]$Line += "`t<varnet>12</varnet> `r`n"
        [string]$Line += "`t</span></td> `r`n"
        [string]$Line += "`r`n"
        out-file -FilePath $FilePath -Encoding unicode -Append -NoClobber -InputObject $Line
    }
    End{}
}


$FilePath = ".\foo.html"
Write-SparkyPageHeader $FilePath
$cpu = Get-RandomArray -ArrayLength 144
$mem = Get-RandomArray -ArrayLength 144
$disk = Get-RandomArray -ArrayLength 144
$net = Get-RandomArray -ArrayLength 144
Write-SparkyPageLine -LineName "Server1" -cpu $cpu -mem $mem -disk $disk -net $net -FilePath $FilePath
$cpu = Get-RandomArray -ArrayLength 144
$mem = Get-RandomArray -ArrayLength 144
$disk = Get-RandomArray -ArrayLength 144
$net = Get-RandomArray -ArrayLength 144
Write-SparkyPageLine -LineName "Server2" -cpu $cpu -mem $mem -disk $disk -net $net -FilePath $FilePath
Write-SparkyPageFooter $FilePath



