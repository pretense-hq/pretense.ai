
/*
=====================
JS Table of Conttent 
=====================
*/
(function ($) {
  "use strict";

  
  /*
------------------------  
24. Fixed-Class
--------------------------
*/
  $(window).scroll(function () {
    if ($(window).scrollTop() > 200) {
      $('.header-area').addClass("sticky");

    } else {
      $('.header-area ').removeClass("sticky");
    }
  });
  /*
------------------------  
24. Toggle-Class
--------------------------
*/
$(document).ready(function () {
  $('#menu-btn').on('click', function () {
    $('#mobile-menu').toggleClass('hidden');
    $(this).toggleClass('active');
  });
});

  /*
------------------------  
24. Animatecss-Class
--------------------------
*/
  function isInViewport($el, offsetPct = 0.2) {
    const rect = $el[0].getBoundingClientRect();
    const winH = $(window).height();
    // visible if at least offsetPct of height is in viewport
    const heightVisible = Math.min(rect.bottom, winH) - Math.max(rect.top, 0);
    return heightVisible >= (rect.height * offsetPct);
  }

  function checkAnimations() {
    $('.animate-onscroll').each(function () {
      const $el = $(this);
      const anim = $el.data('animate') || 'fadeIn';

      // Run only once
      if (!$el.hasClass('animated-once') && isInViewport($el, 0.2)) {
        $el.addClass('animate__animated animate__' + anim + ' animated-once');
      }
    });
  }

  $(window).on('scroll resize load', checkAnimations);
  // initial check
  $(document).ready(checkAnimations);



  /*
------------------------  
24. Hero-Class
--------------------------
*/
  

var swiper = new Swiper(".companySlider", {
  slidesPerView: 2,
  spaceBetween: 24,
  showsPagination: false,
  speed: 1000,
  autoplay: {
    delay: 2000,
  },
  breakpoints: {
    640: {
      slidesPerView: 3,
    },
    991: {
      slidesPerView: 5,
    },
  },
});
var swiper = new Swiper(".teamSlider", {
  slidesPerView: 2,
  spaceBetween: 24,
  centeredSlides: true,
  showsPagination: false,
  speed: 1000,
  autoplay: {
    delay: 2000,
  },
  breakpoints: {
    640: {
      slidesPerView: 2,
    },
    991: {
      slidesPerView: 3,
    },
  },
});


  /*
------------------------  
24. Paralax-Class
--------------------------
*/
$(document).ready(function () {

  $('.accordion-header').click(function () {

    let target = $(this).data('target');
    let parentItem = $(this).closest('.accordion-item');

    // close all
    $('.accordion-content').slideUp();
    $('.accordion-item').removeClass('active');

    // open selected
    if (!$(target).is(':visible')) {
      $(target).slideDown();
      parentItem.addClass('active');
    }

  });

});
  /*
------------------------  
24. Paralax-Class
--------------------------
*/
$(document).ready(function() {
	$('.popupModal').magnificPopup({
		disableOn: 700,
		type: 'iframe',
		mainClass: 'mfp-fade',
		removalDelay: 160,
		preloader: false,

		fixedContentPos: false
	});
});
 
  /*
------------------------  
24. Marquee-Class
--------------------------
*/
function scrolltop(){   
  var wind = $(window);

  wind.on("scroll", function(){ 
      var scrollTop = wind.scrollTop();
      var docHeight = $(document).height();
      var winHeight = wind.height();
      var scrollPercent = (scrollTop / (docHeight - winHeight)) * 100;

      // Show/hide button
      if(scrollPercent >= 10) {
          $(".scroll-top").addClass("show");
      } else {
          $(".scroll-top").removeClass("show");
      }

      // Update percentage (you can display it inside the button)
      $(".scroll-top").text(Math.round(scrollPercent) + "%");
  });

  $(".scroll-top").on("click", function(){
      $("html, body").animate({scrollTop: 0}, 500, "linear");
  });
}

scrolltop();



}(jQuery)); 