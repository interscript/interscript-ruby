# Purpose

The Interscript transliteration/transcription framework in JavaScript.
Supports all Interscript maps.

# Usage

## Install

- Download
  [Interscript.js](https://github.com/interscript/interscript-js/blob/master/interscript.js)
  file directly

- Or in the terminal, you can clone the repository.

  ```shell
  # git clone https://github.com/interscript/interscript-js.git
  # cd ./interscript-js
  ```

## How To Use

- Add a script tag in your html

  ```html
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8" />
      <script src="path/to/interscript.js"></script>
    </head>
    <body></body>
    <script>
      Opal.Interscript.$on_load().then(function () {
        // here use interscript.js
      });
    </script>
  </html>
  ```

- List out the supported systems

  ```javascript
  <script>
    Opal.Interscript.$on_load().then(function(){" "}
    {Object.keys(InterscriptMaps).forEach((system) => {
      document.write(`<option value="${system}" selected>${system}</option>`);
    })}
    );
  </script>
  ```

  Here, **InterscriptMaps** is a global variable defined in the
  interscript.js file, it has the supported systems as json format.
  You can access this object from anywhere you want.

- Get a rule from a system

  ```javascript
  <script>
      const system_code = sel.options[sel.selectedIndex].text;
      Opal.Interscript.$on_load_maps({maps: system_code}).then(function() {
        var data = JSON.parse(InterscriptMaps[system]);
        data.map.rules.forEach(function(rule){
          // write your code here to handle rule
        });
      });
  </script>
  ```

- How to use a system for transliteration

  ```javascript
  <script>
      var system = 'bgnpcgn-rus-Cyrl-Latn-1947';
      var sample = 'Эх, тройка! птица тройка, кто тебя выдумал? знать, у бойкого народа ты могла только родиться, в той земле, что не любит шутить, а ровнем-гладнем разметнулась на полсвета, да и ступай считать версты, пока не зарябит тебе в очи. И не хитрый, кажись, дорожный снаряд, не железным схвачен винтом, а наскоро живьём с одним топором да долотом снарядил и собрал тебя ярославский расторопный мужик. Не в немецких ботфортах ямщик: борода да рукавицы, и сидит чёрт знает на чём; а привстал, да замахнулся, да затянул песню — кони вихрем, спицы в колесах смешались в один гладкий круг, только дрогнула дорога, да вскрикнул в испуге остановившийся пешеход — и вон она понеслась, понеслась, понеслась! Н.В. Гоголь';
      Opal.Interscript.$on_load_maps({maps: system}).then(function() {
        var result = Opal.Interscript.$transliterate(system, sample);
        console.log(result);
      });
  </script>
  ```

## Usage from Node

> **Note**
>
> Interscript is not bundled as a well-behaved module yet; requiring it
> defines a global `Opal` identifier.

Install:

```sh
yarn add interscript
```

Use:

```javascript
require("interscript");

const system = "bgnpcgn-rus-Cyrl-Latn-1947";
const text =
  "Эх, тройка! птица тройка, кто тебя выдумал? знать, у бойкого народа ты могла только родиться, в той земле, что не любит шутить, а ровнем-гладнем разметнулась на полсвета, да и ступай считать версты, пока не зарябит тебе в очи. И не хитрый, кажись, дорожный снаряд, не железным схвачен винтом, а наскоро живьём с одним топором да долотом снарядил и собрал тебя ярославский расторопный мужик. Не в немецких ботфортах ямщик: борода да рукавицы, и сидит чёрт знает на чём; а привстал, да замахнулся, да затянул песню — кони вихрем, спицы в колесах смешались в один гладкий круг, только дрогнула дорога, да вскрикнул в испуге остановившийся пешеход — и вон она понеслась, понеслась, понеслась! Н.В. Гоголь";
Opal.Interscript.$on_load_maps({ maps: system }).then(function () {
  const result = Opal.Interscript.$transliterate(system, text);
  console.log(result);
});
```

## Demo

The demo is included in the repository.

# Development

Interscript.js is generated through Opal on the `interscript` gem in
Ruby.

## Release process

Bump version in package.json; commit and tag the repo appropriately;
push to Github and call `npm publish`.

TODO: Redo build process, generate JS as build artifact and bundle the
code for browser and Node with proper use of exports.
